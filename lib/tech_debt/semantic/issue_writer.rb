# frozen_string_literal: true

require "json"
require_relative "llm_client"

module TechDebt
  module Semantic
    # Second-pass LLM call: enriches triage findings with acceptance criteria and baseline metrics.
    class IssueWriter
      def initialize(config, prompt_path:)
        @config = config
        @prompt_path = prompt_path
        @llm_client = LlmClient.new(config)
      end

      def call(findings)
        return findings if findings.empty?
        return findings unless File.file?(@prompt_path)

        system_prompt = File.read(@prompt_path)
        user_prompt = build_user_prompt(findings)
        content = @llm_client.triage(system_prompt: system_prompt, user_prompt: user_prompt)
        enriched = parse_json_array(content)
        merge_findings(findings, enriched)
      rescue StandardError => e
        warn "[wall-e] IssueWriter failed (#{e.class}: #{e.message}); using triage output as-is"
        findings
      end

      private

      def build_user_prompt(findings)
        JSON.pretty_generate(
          instruction: "Enrich each finding with acceptance_criteria, baseline_metrics, and polished description/suggested_refactor. Return a JSON array in the same order and cardinality as `findings`.",
          findings: findings
        )
      end

      def merge_findings(original, enriched)
        return original unless enriched.is_a?(Array)
        return original if enriched.size != original.size

        original.each_with_index.map do |item, idx|
          extra = enriched[idx]
          next item unless extra.is_a?(Hash)

          item.merge(
            "description" => extra["description"] || item["description"],
            "suggested_refactor" => extra["suggested_refactor"] || item["suggested_refactor"],
            "acceptance_criteria" => Array(extra["acceptance_criteria"] || item["acceptance_criteria"]),
            "baseline_metrics" => merge_baseline(item["baseline_metrics"], extra["baseline_metrics"])
          )
        end
      end

      def merge_baseline(primary, secondary)
        a = primary.is_a?(Hash) ? primary : {}
        b = secondary.is_a?(Hash) ? secondary : {}
        a.merge(b)
      end

      def parse_json_array(content)
        raw = strip_code_fences(content)
        parsed = JSON.parse(raw)
        return parsed if parsed.is_a?(Array)

        raise "LLM response was not an array"
      rescue JSON::ParserError => e
        warn "[wall-e] IssueWriter JSON parse error: #{e.message}"
        nil
      end

      def strip_code_fences(content)
        content.gsub(/\A```(?:json)?\s*/m, "").gsub(/\s*```\z/m, "").strip
      end
    end
  end
end
