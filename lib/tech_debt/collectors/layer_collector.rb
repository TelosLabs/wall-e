# frozen_string_literal: true

require_relative "base_collector"

module TechDebt
  module Collectors
    # Grep-based collector for layered architecture violations.
    # Surfaces files that static complexity/dead-code tools would miss,
    # so the LLM can confirm or reject the candidate with full code context.
    class LayerCollector < BaseCollector
      def call
        target_files.flat_map { |file| analyze_file(file) }
      end

      private

      def analyze_file(file)
        content = File.read(file)
        findings = []
        findings.concat(current_attribute_violations(file, content)) if model_file?(file)
        findings.concat(anemic_job_signals(file, content)) if job_file?(file)
        findings
      rescue StandardError => e
        warn "[wall-e] LayerCollector: skipping #{file} — #{e.message}"
        []
      end

      def model_file?(file)
        file.match?(%r{/app/models/})
      end

      def job_file?(file)
        file.match?(%r{/app/jobs/})
      end

      def current_attribute_violations(file, content)
        return [] unless content.match?(/Current\.\w+/)

        [{
          file: file,
          identifier: extract_class_name(content) || File.basename(file, ".rb"),
          type: "leaked_business_logic",
          detail: "References Current.* inside a model — layer violation. " \
                  "Current context is unavailable in background jobs and rake tasks, " \
                  "causing silent nil failures. Pass the value as an explicit parameter instead.",
          score: 8
        }]
      end

      def anemic_job_signals(file, content)
        return [] unless content.include?("def perform")

        body = extract_perform_body(content)
        return [] if body.nil? || body.size != 1
        return [] unless body[0].match?(/\A\w+\.\w+[\w!?]*(\(.*\))?\z/)

        [{
          file: file,
          identifier: "#{extract_class_name(content)}#perform",
          type: "leaked_business_logic",
          detail: "Job perform delegates entirely to a single model method with no added logic — " \
                  "anemic job. Consider using the active_job-performs gem to eliminate the " \
                  "separate job class and declare background execution directly on the model.",
          score: 5
        }]
      end

      def extract_perform_body(content)
        match = content.match(/def perform\([^)]*\)\n(.*?)\n\s*end/m)
        return nil unless match

        match[1].split("\n").map(&:strip).reject(&:empty?)
      end

      def extract_class_name(content)
        match = content.match(/^class\s+(\w+)/)
        match[1] if match
      end
    end
  end
end
