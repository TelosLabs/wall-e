# frozen_string_literal: true

require 'octokit'
require_relative 'fingerprint'

module TechDebt
  module Github
    class IssueManager
      AUTO_LABEL_DEFINITIONS = [
        { 'name' => 'ai-detected', 'color' => '7057ff' },
        { 'name' => 'severity:high', 'color' => 'b60205' },
        { 'name' => 'severity:medium', 'color' => 'fbca04' },
        { 'name' => 'severity:low', 'color' => '0e8a16' }
      ].freeze

      AUTO_LABEL_NAMES = AUTO_LABEL_DEFINITIONS.map { |label| label.fetch('name') }.freeze

      attr_reader :repo

      def initialize(config)
        token = ENV.fetch('GITHUB_TOKEN')
        @repo = config.github['repo'] || ENV['GITHUB_REPOSITORY']
        raise ArgumentError, 'github.repo or GITHUB_REPOSITORY is required' if @repo.nil? || @repo.empty?

        @config = config
        @client = Octokit::Client.new(access_token: token)
      end

      # Ensure that the labels are created in the repository
      def ensure_labels!
        labels_to_ensure.each do |label|
          @client.add_label(@repo, label.fetch('name'), label.fetch('color'))
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
        title = "#{@config.github.fetch('issue_prefix', '[Tech Debt Agent]')} #{item.fetch('title')}"
        body = build_issue_body(item, fingerprint)
        labels = base_labels + ['ai-detected', severity_label_for(item)]
        @client.create_issue(@repo, title, body, labels: labels.uniq)
      end

      private

      def configured_labels
        @config.github.fetch('labels', [])
      end

      def labels_to_ensure
        labels_by_name = {}
        configured_labels.each { |label| labels_by_name[label.fetch('name')] = label }
        AUTO_LABEL_DEFINITIONS.each { |label| labels_by_name[label.fetch('name')] ||= label }
        labels_by_name.values
      end

      def base_labels
        configured_labels
          .map { |label| label.fetch('name') }
          .reject { |name| AUTO_LABEL_NAMES.include?(name) || name.start_with?('severity:') }
      end

      def severity_label_for(item)
        "severity:#{item.fetch('severity').to_s.downcase}"
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
          - **Score details:** #{score_details(item)}

          #{Github::Fingerprint.to_html_comment(fingerprint)}
        BODY
      end

      def score_details(item)
        debt_type = item.fetch('debt_type')
        score = item.fetch('score', 0)

        case debt_type
        when 'high_complexity'
          threshold = @config.analysis.dig('debt_types', 'high_complexity', 'flog_threshold')
          return "Complexity score: #{score}/#{threshold} threshold (higher is worse)" if threshold

          "Complexity score: #{score} (higher is worse)"
        when 'dead_code'
          "Dead-code signal score: #{score} (binary/static detector signal, not a complexity scale)"
        when 'semantic_duplication'
          threshold = @config.analysis.dig('debt_types', 'semantic_duplication', 'similarity_threshold')
          return "Impact score: #{score}; similarity threshold configured at #{threshold}" if threshold

          "Impact score: #{score} for duplicated behavior"
        else
          "Impact score: #{score} (0-100 heuristic used for prioritization)"
        end
      end
    end
  end
end
