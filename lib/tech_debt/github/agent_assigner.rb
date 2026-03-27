# frozen_string_literal: true

require 'octokit'

module TechDebt
  module Github
    class AgentAssigner
      SEVERITY_RANK = {
        'low' => 0,
        'medium' => 1,
        'high' => 2
      }.freeze

      DEFAULT_AGENT_COMMENT_PROMPT = <<~PROMPT.strip.freeze
        Analyze and fix this tech debt issue. Read the description for file path,
        debt type, and suggested refactoring approach. Open a PR when done.
      PROMPT

      def initialize(config)
        @config = config
        raw_settings = config.auto_assign
        @settings = raw_settings.is_a?(Hash) ? raw_settings : {}
        @repo = config.github['repo'] || ENV['GITHUB_REPOSITORY']
        raw_filters = @settings['filters']
        @filters = raw_filters.is_a?(Hash) ? raw_filters : {}
        @agent = @settings.fetch('agent', 'copilot').to_s.downcase
        @token_env = @settings.fetch('token_env', 'AGENT_ASSIGN_TOKEN')

        token = resolve_token
        @client = Octokit::Client.new(access_token: token)
      end

      def assign(item, issue_number)
        return false unless eligible?(item)

        case @agent
        when 'copilot'
          assign_copilot(issue_number)
        when 'cursor'
          assign_cursor(issue_number, item)
        when 'opencode'
          assign_opencode(issue_number, item)
        when 'claude'
          assign_claude(issue_number, item)
        else
          warn "Unknown auto_assign.agent '#{@agent}', skipping assignment"
          return false
        end

        true
      rescue Octokit::NotFound => e
        warn "[wall-e] Auto-assignment failed for issue ##{issue_number}: #{e.message}. " \
             'For Copilot: ensure coding agent is enabled for the repo/org and the token ' \
             'has Issues write + Metadata read permissions (use a PAT from a Copilot-licensed user). ' \
             'For Cursor/OpenCode/Claude comments: confirm the token can create issue comments.'
        false
      rescue StandardError => e
        warn "[wall-e] Auto-assignment failed for issue ##{issue_number}: #{e.class} - #{e.message}"
        false
      end

      private

      def eligible?(item)
        passes_severity_filter?(item) && passes_debt_type_filter?(item)
      end

      def passes_severity_filter?(item)
        item_rank = SEVERITY_RANK.fetch(item.fetch('severity').to_s.downcase, 0)
        min_rank = SEVERITY_RANK.fetch(min_severity, 0)
        item_rank >= min_rank
      end

      def min_severity
        @filters.fetch('min_severity', 'low').to_s.downcase
      end

      def passes_debt_type_filter?(item)
        allowed = Array(@filters['debt_types']).map(&:to_s)
        return true if allowed.empty?

        allowed.include?(item.fetch('debt_type').to_s)
      end

      def resolve_token
        explicit = ENV[@token_env]
        unless explicit.to_s.strip.empty?
          warn "[wall-e] Using #{@token_env} for auto-assignment"
          return explicit
        end

        fallback = ENV['GITHUB_TOKEN']
        if fallback.to_s.strip.empty?
          warn "[wall-e] WARNING: Neither #{@token_env} nor GITHUB_TOKEN is set; auto-assignment will fail"
        else
          warn "[wall-e] #{@token_env} not set, falling back to GITHUB_TOKEN for auto-assignment"
        end
        fallback
      end

      COPILOT_ASSIGNEE = 'copilot-swe-agent[bot]'
      ASSIGN_PRE_DELAY = 5
      ASSIGN_RETRY_ATTEMPTS = 3
      ASSIGN_RETRY_BASE_DELAY = 2

      def assign_copilot(issue_number)
        attempts = 0
        sleep(ASSIGN_PRE_DELAY)

        begin
          @client.add_assignees(@repo, issue_number, [COPILOT_ASSIGNEE])
        rescue Octokit::NotFound
          attempts += 1
          raise if attempts >= ASSIGN_RETRY_ATTEMPTS

          sleep(ASSIGN_RETRY_BASE_DELAY * attempts)
          retry
        end
      end

      def assign_cursor(issue_number, item)
        @client.add_comment(@repo, issue_number, build_cursor_prompt(item, issue_number))
      end

      def build_cursor_prompt(item, issue_number)
        agent_comment_with_context("@cursor #{DEFAULT_AGENT_COMMENT_PROMPT}", item, issue_number: issue_number)
      end

      def assign_opencode(issue_number, item)
        @client.add_comment(@repo, issue_number, build_opencode_prompt(item, issue_number))
      end

      def build_opencode_prompt(item, issue_number)
        agent_comment_with_context("/opencode #{DEFAULT_AGENT_COMMENT_PROMPT}", item, issue_number: issue_number)
      end

      def assign_claude(issue_number, item)
        @client.add_comment(@repo, issue_number, build_claude_prompt(item, issue_number))
      end

      def build_claude_prompt(item, issue_number)
        agent_comment_with_context("@claude #{DEFAULT_AGENT_COMMENT_PROMPT}", item, issue_number: issue_number)
      end

      def agent_comment_with_context(prompt, item, issue_number:)
        [
          prompt,
          '',
          "Fixes ##{issue_number}",
          '',
          'Context:',
          "- debt_type: #{item.fetch('debt_type')}",
          "- severity: #{item.fetch('severity')}",
          "- file_path: #{item.fetch('file_path')}"
        ].join("\n")
      end
    end
  end
end
