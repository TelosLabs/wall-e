# frozen_string_literal: true

require "octokit"
require_relative "fingerprint"

module TechDebt
  module Github
    class IssueManager
      attr_reader :repo

      def initialize(config)
        token = ENV.fetch("GITHUB_TOKEN")
        @repo = config.github["repo"] || ENV["GITHUB_REPOSITORY"]
        raise ArgumentError, "github.repo or GITHUB_REPOSITORY is required" if @repo.nil? || @repo.empty?

        @config = config
        @client = Octokit::Client.new(access_token: token)
      end

      def ensure_labels!
        @config.github.fetch("labels", []).each do |label|
          @client.add_label(@repo, label.fetch("name"), label.fetch("color"))
        rescue Octokit::UnprocessableEntity
          next
        end
      end

      def issue_exists_by_fingerprint?(fingerprint)
        query = "repo:#{@repo} is:issue in:body #{Github::Fingerprint::COMMENT_PREFIX}#{fingerprint}"
        result = @client.search_issues(query, per_page: 1)
        result.total_count.positive?
      end

      def create_issue(item, fingerprint)
        title = "#{@config.github.fetch('issue_prefix', '[Tech Debt]')} #{item.fetch('title')}"
        body = build_issue_body(item, fingerprint)
        labels = default_labels + ["severity:#{item.fetch('severity')}"]
        @client.create_issue(@repo, title, body, labels: labels.uniq)
      end

      private

      def default_labels
        @config.github.fetch("labels", []).map { |label| label["name"] }
      end

      def build_issue_body(item, fingerprint)
        <<~BODY
          **Type:** #{item.fetch('debt_type')} | **Severity:** #{item.fetch('severity')} | **File:** `#{item.fetch('file_path')}`

          ### Description
          #{item.fetch('description')}

          ### Suggested Refactor
          #{item.fetch('suggested_refactor')}

          ### Detection Metadata
          - **Detected by:** AI Tech Debt Agent (v1)
          - **Run date:** #{Time.now.utc.iso8601}
          - **Score:** #{item.fetch('score', 0)}

          #{Github::Fingerprint.to_html_comment(fingerprint)}
        BODY
      end
    end
  end
end
