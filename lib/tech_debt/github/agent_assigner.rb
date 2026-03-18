# frozen_string_literal: true

require "octokit"

module TechDebt
  module Github
    class AgentAssigner
      SEVERITY_RANK = {
        "low" => 0,
        "medium" => 1,
        "high" => 2
      }.freeze

      DEFAULT_CURSOR_PROMPT = <<~PROMPT.strip.freeze
        Analyze and fix this tech debt issue. Read the description for file path,
        debt type, and suggested refactoring approach. Open a PR when done.
      PROMPT

      def initialize(config)
        @config = config
        raw_settings = config.auto_assign
        @settings = raw_settings.is_a?(Hash) ? raw_settings : {}
        @repo = config.github["repo"] || ENV["GITHUB_REPOSITORY"]
        raw_filters = @settings["filters"]
        @filters = raw_filters.is_a?(Hash) ? raw_filters : {}
        @agent = @settings.fetch("agent", "copilot").to_s.downcase
        @token_env = @settings.fetch("token_env", "AGENT_ASSIGN_TOKEN")

        token = ENV[@token_env]
        token = ENV["GITHUB_TOKEN"] if token.to_s.strip.empty?
        @client = Octokit::Client.new(access_token: token)
      end

      def assign(item, issue_number)
        return false unless eligible?(item)

        case @agent
        when "copilot"
          assign_copilot(issue_number)
        when "cursor"
          assign_cursor(issue_number, item)
        else
          warn "Unknown auto_assign.agent '#{@agent}', skipping assignment"
          return false
        end

        true
      rescue StandardError => e
        warn "Auto-assignment failed for issue ##{issue_number}: #{e.class} - #{e.message}"
        false
      end

      private

      def eligible?(item)
        passes_severity_filter?(item) && passes_debt_type_filter?(item)
      end

      def passes_severity_filter?(item)
        item_rank = SEVERITY_RANK.fetch(item.fetch("severity").to_s.downcase, 0)
        min_rank = SEVERITY_RANK.fetch(min_severity, 0)
        item_rank >= min_rank
      end

      def min_severity
        @filters.fetch("min_severity", "low").to_s.downcase
      end

      def passes_debt_type_filter?(item)
        allowed = Array(@filters["debt_types"]).map(&:to_s)
        return true if allowed.empty?

        allowed.include?(item.fetch("debt_type").to_s)
      end

      def assign_copilot(issue_number)
        @client.add_assignees(@repo, issue_number, ["copilot"])
      end

      def assign_cursor(issue_number, item)
        @client.add_comment(@repo, issue_number, build_cursor_prompt(item))
      end

      def build_cursor_prompt(item)
        base_prompt = @settings.fetch("cursor_prompt", DEFAULT_CURSOR_PROMPT).to_s.strip
        prompt = base_prompt.start_with?("@cursor") ? base_prompt : "@cursor #{base_prompt}"

        [
          prompt,
          "",
          "Context:",
          "- debt_type: #{item.fetch('debt_type')}",
          "- severity: #{item.fetch('severity')}",
          "- file_path: #{item.fetch('file_path')}"
        ].join("\n")
      end
    end
  end
end
