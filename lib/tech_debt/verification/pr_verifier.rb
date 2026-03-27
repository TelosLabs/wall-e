# frozen_string_literal: true

require "octokit"
require_relative "../github/issue_manager"
require_relative "llm_verifier"
require_relative "result_reporter"
require_relative "static_verifier"

module TechDebt
  module Verification
    class PrVerifier
      ISSUE_REF = /\b(?:fix(?:es)?|close[sd]?|resolve[sd]?)\s*#(\d+)\b/i

      def initialize(config, pr_number:, verification_prompt_path:, dry_run: false)
        @config = config
        @pr_number = pr_number.to_i
        @verification_prompt_path = verification_prompt_path
        @dry_run = dry_run
        @repo = config.github["repo"] || ENV["GITHUB_REPOSITORY"]
        raise ArgumentError, "github.repo or GITHUB_REPOSITORY is required" if @repo.nil? || @repo.empty?

        @client = Octokit::Client.new(access_token: ENV.fetch("GITHUB_TOKEN"))
      end

      def run
        issue_numbers = extract_issue_numbers
        payloads = issue_numbers.filter_map { |n| load_verified_payload(n) }

        if payloads.empty?
          return {
            "status" => "skipped",
            "reason" => "No linked issues with wall_e_verification metadata.",
            "pull_request" => @pr_number
          }
        end

        rb_files, patches = pull_request_file_index
        static = StaticVerifier.new(@config, changed_rb_files: rb_files)

        llm_verifier = nil
        results = payloads.map do |entry|
          static_out = static.verify(entry[:payload])
          if static_out["conclusive"]
            build_static_result(entry[:issue_number], entry[:payload], static_out)
          else
            llm_verifier ||= init_llm_verifier
            llm_out = llm_verifier.verify(entry[:payload], pr_number: @pr_number, patches_by_file: patches)
            build_llm_result(entry[:issue_number], entry[:payload], llm_out)
          end
        end

        ResultReporter.new(client: @client, repo: @repo, pr_number: @pr_number, dry_run: @dry_run).post!(
          results,
          close_on_pass: @config.close_issues_on_verification_pass?
        )

        {
          "status" => "completed",
          "pull_request" => @pr_number,
          "results" => results
        }
      end

      private

      def init_llm_verifier
        unless File.file?(@verification_prompt_path)
          raise ArgumentError, "Verification prompt not found: #{@verification_prompt_path}"
        end

        LlmVerifier.new(@config, prompt_path: @verification_prompt_path)
      end

      def extract_issue_numbers
        pr = @client.pull_request(@repo, @pr_number)
        nums = []
        pr.body.to_s.scan(ISSUE_REF) { nums << Regexp.last_match(1).to_i }
        @client.pull_request_commits(@repo, @pr_number).each do |c|
          msg = c.commit&.message
          msg.to_s.scan(ISSUE_REF) { nums << Regexp.last_match(1).to_i }
        end
        nums.uniq.sort
      end

      def load_verified_payload(issue_number)
        issue = @client.issue(@repo, issue_number)
        payload = Github::IssueManager.parse_verification_from_body(issue.body.to_s)
        return nil unless payload

        { issue_number: issue_number, payload: payload }
      end

      def pull_request_file_index
        rb_files = []
        patches = {}
        @client.pull_request_files(@repo, @pr_number).each do |f|
          next unless f.filename.end_with?(".rb")

          rb_files << f.filename
          patches[f.filename] = f.patch.to_s
        end
        [rb_files.uniq, patches]
      end

      def build_static_result(issue_number, payload, static_out)
        passed = static_out["passed"]
        {
          "issue_number" => issue_number,
          "verification" => payload,
          "passed" => passed,
          "verdict" => passed ? "pass" : "fail",
          "source" => "static",
          "explanation" => static_out["explanation"],
          "criteria_results" => []
        }
      end

      def build_llm_result(issue_number, payload, llm_out)
        verdict = llm_out["verdict"]
        {
          "issue_number" => issue_number,
          "verification" => payload,
          "passed" => verdict == "pass",
          "verdict" => verdict,
          "source" => "llm",
          "explanation" => llm_out["explanation"],
          "criteria_results" => llm_out["criteria_results"]
        }
      end
    end
  end
end
