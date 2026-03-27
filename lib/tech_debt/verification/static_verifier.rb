# frozen_string_literal: true

require "open3"
require "shellwords"
require_relative "../collectors/debride_collector"

module TechDebt
  module Verification
    # Tier-1 checks using flog/debride/file reads (no LLM).
    class StaticVerifier
      def initialize(config, changed_rb_files:)
        @config = config
        @changed_rb_files = Array(changed_rb_files).map(&:to_s).uniq
      end

      # @param payload [Hash] parsed wall_e_verification JSON from the issue body
      # @return [Hash] keys: conclusive (bool), passed (bool), explanation (String)
      def verify(payload)
        debt = payload["debt_type"].to_s
        case debt
        when "high_complexity"
          verify_high_complexity(payload)
        when "dead_code"
          verify_dead_code(payload)
        when "leaked_business_logic"
          verify_leaked_business_logic(payload)
        else
          inconclusive("No static verifier for debt_type `#{debt}`")
        end
      end

      private

      def verify_high_complexity(payload)
        path = payload["file_path"].to_s
        return inconclusive("Missing file_path") if path.empty?

        files = scan_targets(path)
        return inconclusive("PR does not include `#{path}`; file may have moved (needs LLM).") if files.empty?

        scores = flog_scores_for_files(files)
        identifier = payload["identifier"].to_s
        threshold = @config.flog_threshold

        unless scores.key?(identifier)
          return conclusive(true, "Method `#{identifier}` is not reported above the flog threshold (likely reduced or removed).")
        end

        new_score = scores[identifier]
        baseline = payload.dig("baseline_metrics", "flog_score")
        baseline_f = baseline.nil? ? nil : baseline.to_f

        passed =
          (new_score <= threshold) ||
          (baseline_f&.positive? && new_score <= baseline_f * 0.8)

        msg = "Flog score for `#{identifier}` is #{new_score} (threshold #{threshold}" \
              "#{baseline_f&.positive? ? ", baseline was #{baseline_f}" : ''})."
        conclusive(passed, msg)
      end

      def verify_dead_code(payload)
        path = payload["file_path"].to_s
        identifier = payload["identifier"].to_s
        return inconclusive("Missing identifier") if identifier.empty?

        files = scan_targets(path)
        return inconclusive("PR does not include `#{path}`.") if files.empty?

        rows = Collectors::DebrideCollector.new(@config, files: files).call
        still_dead = rows.any? { |r| r[:identifier] == identifier }
        msg = still_dead ? "Debride still reports `#{identifier}` as uncalled." : "`#{identifier}` no longer appears in debride output for changed files."
        conclusive(!still_dead, msg)
      end

      def verify_leaked_business_logic(payload)
        path = payload["file_path"].to_s
        metrics = payload["baseline_metrics"]
        return inconclusive("No static Current.* check for this finding (use LLM).") unless metrics.is_a?(Hash) && metrics["pattern_present"] == true
        return inconclusive("Not a model path; static Current scan skipped.") unless path.match?(%r{/app/models/})

        files = scan_targets(path)
        return inconclusive("PR does not include `#{path}`.") if files.empty?

        content = File.read(path)
        still = content.match?(/Current\.\w+/)
        msg = still ? "Model still contains `Current.*` references." : "No `Current.*` references remain in this file."
        conclusive(!still, msg)
      end

      def scan_targets(path)
        return [path] if @changed_rb_files.include?(path)
        return [path] if File.file?(path)

        []
      end

      def flog_scores_for_files(files)
        return {} if files.empty?

        stdout, stderr, status = Open3.capture3(
          "bundle exec flog -a #{files.map { |p| Shellwords.escape(p) }.join(' ')}"
        )
        warn "[wall-e] flog exited #{status.exitstatus}" unless status.success?
        parse_flog_scores([stdout, stderr].join("\n"))
      end

      def parse_flog_scores(output)
        scores = {}
        output.each_line do |line|
          match = line.match(/^\s*(?<score>\d+(?:\.\d+)?):\s+(?<rest>.+)$/)
          next unless match

          rest = match[:rest].strip
          next if rest.start_with?("flog ")

          score = match[:score].to_f
          file = rest[%r{(?<path>[\w\/\.\-]+\.rb):\d+(?:-\d+)?}, :path]
          next unless file

          identifier = rest.sub(%r{\s+[\w\/\.\-]+\.rb:\d+(?:-\d+)?\s*$}, "")
          next if identifier =~ /\Amain#none\z/i

          scores[identifier] = score
        end
        scores
      end

      def conclusive(passed, explanation)
        { "conclusive" => true, "passed" => passed, "explanation" => explanation }
      end

      def inconclusive(explanation)
        { "conclusive" => false, "passed" => false, "explanation" => explanation }
      end
    end
  end
end
