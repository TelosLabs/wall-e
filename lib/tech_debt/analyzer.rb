# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "collectors/debride_collector"
require_relative "collectors/complexity_collector"
require_relative "github/fingerprint"
require_relative "github/agent_assigner"
require_relative "github/issue_manager"
require_relative "semantic/triage"

module TechDebt
  class Analyzer
    def initialize(config, prompt_path:)
      @config = config
      @prompt_path = prompt_path
    end

    def run(dry_run: false, skip_llm: false)
      candidates = collect_candidates
      findings = if skip_llm
                   candidates_to_findings(candidates)
                 else
                   Semantic::Triage.new(@config, prompt_path: @prompt_path).call(candidates)
                 end

      summary = process_findings(findings, dry_run: dry_run)
      write_summary(summary) if @config.reporting["generate_summary"]
      summary
    end

    private

    def collect_candidates
      collectors = [
        Collectors::DebrideCollector.new(@config),
        Collectors::ComplexityCollector.new(@config)
      ]

      collectors.flat_map(&:call)
    end

    def candidates_to_findings(candidates)
      severity_map = @config.analysis.fetch("debt_types", {}).transform_values { |v| v["severity"] || "medium" }
      candidates.map do |item|
        {
          "file_path" => item[:file],
          "identifier" => item[:identifier],
          "debt_type" => item[:type],
          "severity" => severity_map.fetch(item[:type], "medium"),
          "title" => "#{item[:type].tr('_', ' ')} detected for #{item[:identifier]}",
          "description" => item[:detail],
          "suggested_refactor" => "Review and refactor this section following Rails conventions.",
          "canonical_pattern" => nil,
          "score" => item[:score]
        }
      end
    end

    def process_findings(findings, dry_run:)
      findings = findings.first(max_issues_per_run)
      return dry_run_summary(findings) if dry_run

      manager = Github::IssueManager.new(@config)
      manager.ensure_labels!
      assigner = build_assigner

      created = []
      skipped = []
      findings.each do |item|
        fingerprint = Github::Fingerprint.for_item(item)
        if manager.issue_exists_by_fingerprint?(fingerprint)
          skipped << item.merge("fingerprint" => fingerprint, "reason" => "already_reported")
          next
        end

        issue = manager.create_issue(item, fingerprint)
        agent_assigned = assigner ? assigner.assign(item, issue.number) : false
        created << {
          "number" => issue.number,
          "url" => issue.html_url,
          "title" => issue.title,
          "fingerprint" => fingerprint,
          "agent_assigned" => agent_assigned
        }
      end

      {
        "mode" => "live",
        "total_findings" => findings.size,
        "created_count" => created.size,
        "skipped_count" => skipped.size,
        "created" => created,
        "skipped" => skipped
      }
    end

    def dry_run_summary(findings)
      simulated = findings.map do |item|
        item.merge("fingerprint" => Github::Fingerprint.for_item(item))
      end
      {
        "mode" => "dry_run",
        "total_findings" => findings.size,
        "would_create_count" => simulated.size,
        "would_create" => simulated
      }
    end

    def write_summary(summary)
      path = @config.reporting.fetch("summary_path", "tmp/tech_debt_report.json")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(summary))
    end

    def max_issues_per_run
      @config.github.fetch("max_issues_per_run", 10).to_i
    end

    def build_assigner
      return nil unless @config.auto_assign["enabled"]

      Github::AgentAssigner.new(@config)
    end
  end
end
