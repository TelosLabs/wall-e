# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "collectors/debride_collector"
require_relative "collectors/complexity_collector"
require_relative "collectors/flay_collector"
require_relative "collectors/layer_collector"
require_relative "github/fingerprint"
require_relative "github/agent_assigner"
require_relative "github/issue_manager"
require_relative "semantic/issue_writer"
require_relative "semantic/triage"

module TechDebt
  class Analyzer
    def initialize(config, prompt_path:, issue_writer_prompt_path: ".github/prompts/wall_e_issue_writer.md")
      @config = config
      @prompt_path = prompt_path
      @issue_writer_prompt_path = issue_writer_prompt_path
    end

    def run(dry_run: false, skip_llm: false, max_issues: nil)
      @max_issues_override = max_issues
      candidates = collect_candidates
      findings = if skip_llm
                   candidates_to_findings(candidates)
                 else
                   Semantic::Triage.new(@config, prompt_path: @prompt_path).call(candidates)
                 end

      findings = Semantic::IssueWriter.new(@config, prompt_path: @issue_writer_prompt_path).call(findings) unless skip_llm
      findings.each { |item| normalize_verification_fields!(item) }

      summary = process_findings(findings, dry_run: dry_run)
      write_summary(summary)
      summary
    end

    private

    def collect_candidates
      collectors = [
        Collectors::DebrideCollector.new(@config),
        Collectors::ComplexityCollector.new(@config),
        Collectors::FlayCollector.new(@config),
        Collectors::LayerCollector.new(@config)
      ]

      collectors.flat_map(&:call)
    end

    def candidates_to_findings(candidates)
      candidates.map do |item|
        debt_type = item[:type].to_s
        score = item[:score]
        baseline_metrics = skip_llm_baseline_metrics(debt_type, score)
        {
          "file_path" => item[:file],
          "identifier" => item[:identifier],
          "debt_type" => debt_type,
          "severity" => "medium",
          "title" => "#{debt_type.tr('_', ' ')} detected for #{item[:identifier]}",
          "description" => item[:detail],
          "suggested_refactor" => "Review and refactor this section following Rails conventions.",
          "canonical_pattern" => nil,
          "score" => score,
          "acceptance_criteria" => [],
          "baseline_metrics" => baseline_metrics
        }
      end
    end

    def skip_llm_baseline_metrics(debt_type, score)
      case debt_type
      when "high_complexity"
        { "flog_score" => score.to_f }
      when "dead_code"
        { "method_present" => true }
      when "leaked_business_logic"
        { "pattern_present" => true }
      when "structural_duplication"
        { "flay_mass" => score.to_f }
      else
        {}
      end
    end

    def normalize_verification_fields!(item)
      item["acceptance_criteria"] = Array(item["acceptance_criteria"]).map(&:to_s).map(&:strip).reject(&:empty?)
      unless item["baseline_metrics"].is_a?(Hash) && item["baseline_metrics"].any?
        item["baseline_metrics"] = infer_baseline_metrics(item)
      end
      item["baseline_metrics"] = {} unless item["baseline_metrics"].is_a?(Hash)
      return if item["acceptance_criteria"].any?

      item["acceptance_criteria"] = [fallback_acceptance_criterion(item)]
    end

    def fallback_acceptance_criterion(item)
      "Debt type `#{item.fetch('debt_type')}` for `#{item.fetch('identifier')}` in `#{item.fetch('file_path')}` is fully addressed in the PR without relocating the problem."
    end

    def infer_baseline_metrics(item)
      existing = item["baseline_metrics"]
      return existing if existing.is_a?(Hash) && existing.any?

      case item.fetch("debt_type").to_s
      when "high_complexity"
        { "flog_score" => item.fetch("score", 0).to_f }
      when "dead_code"
        { "method_present" => true }
      when "leaked_business_logic"
        { "pattern_present" => true }
      when "structural_duplication"
        { "flay_mass" => item.fetch("score", 0).to_f }
      else
        {}
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
      path = TechDebt::Config::SUMMARY_PATH
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(summary))
    end

    def max_issues_per_run
      (@max_issues_override || @config.github.fetch("max_issues_per_run", 10)).to_i
    end

    def build_assigner
      return nil unless @config.auto_assign["enabled"]

      Github::AgentAssigner.new(@config)
    end
  end
end
