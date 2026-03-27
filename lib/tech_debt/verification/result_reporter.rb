# frozen_string_literal: true

require "octokit"

module TechDebt
  module Verification
    class ResultReporter
      def initialize(client:, repo:, pr_number:, dry_run: false)
        @client = client
        @repo = repo
        @pr_number = pr_number
        @dry_run = dry_run
      end

      def post!(results, close_on_pass: false)
        body = format_comment(results)
        if @dry_run
          warn "[wall-e] Dry run — PR comment would be:\n#{body}"
          return
        end

        @client.add_comment(@repo, @pr_number, body)
        return unless close_on_pass && all_pass?(results)

        close_linked_issues(results)
      end

      private

      def all_pass?(results)
        results.all? { |r| r["verdict"] == "pass" }
      end

      def close_linked_issues(results)
        results.each do |r|
          next unless r["passed"]

          num = r["issue_number"]
          next unless num

          @client.close_issue(@repo, num)
        rescue Octokit::Error => e
          warn "[wall-e] Could not close issue ##{num}: #{e.message}"
        end
      end

      def format_comment(results)
        lines = ["## wall-e PR verification", ""]
        if results.empty?
          lines << "_No verification results._"
          return lines.join("\n")
        end

        verdicts = results.map { |r| r["verdict"] }
        overall =
          if verdicts.all? { |v| v == "pass" }
            "✅ **All linked checks passed.**"
          elsif verdicts.any? { |v| v == "pass" || v == "partial" }
            "⚠️ **Partial pass** — some checks still need attention."
          else
            "❌ **Verification failed.**"
          end
        lines << overall
        lines << ""

        results.each_with_index do |r, i|
          lines << "### Issue ##{r['issue_number']} — `#{r.dig('verification', 'identifier')}`"
          lines << "- **Source:** #{r['source']}"
          lines << "- **Passed:** #{r['passed']}"
          lines << "- **Verdict:** #{r['verdict']}" if r["verdict"]
          lines << "- **Detail:** #{r['explanation']}"
          append_criteria(lines, r["criteria_results"])
          lines << ""
        end

        lines.join("\n").strip
      end

      def append_criteria(lines, criteria_results)
        list = Array(criteria_results)
        return if list.empty?

        lines << "- **Criteria:**"
        list.each do |c|
          next unless c.is_a?(Hash)

          ok = c["passed"]
          mark = ok ? "☑" : "☐"
          lines << "  - #{mark} #{c['criterion']}: #{c['note']}"
        end
      end
    end
  end
end
