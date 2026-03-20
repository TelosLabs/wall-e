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

        token = resolve_token
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

      def resolve_token
        explicit = ENV[@token_env]
        unless explicit.to_s.strip.empty?
          warn "[wall-e] Using #{@token_env} for auto-assignment"
          return explicit
        end

        fallback = ENV["GITHUB_TOKEN"]
        if fallback.to_s.strip.empty?
          warn "[wall-e] WARNING: Neither #{@token_env} nor GITHUB_TOKEN is set; auto-assignment will fail"
        else
          warn "[wall-e] #{@token_env} not set, falling back to GITHUB_TOKEN for auto-assignment"
        end
        fallback
      end

      def assign_copilot(issue_number)
        unless @client.check_assignee(@repo, "copilot")
          warn "[wall-e] 'copilot' is not a valid assignee for #{@repo}. " \
               "Ensure Copilot coding agent is enabled for the repository/org " \
               "and the token has Issues write permission."
          return
        end

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
