# frozen_string_literal: true

require "json"
require_relative "../semantic/llm_client"

module TechDebt
  module Verification
    class LlmVerifier
      def initialize(config, prompt_path:)
        @config = config
        @prompt_path = prompt_path
        @llm = Semantic::LlmClient.new(config)
      end

      # @return [Hash] verdict, explanation, criteria_results
      def verify(payload, pr_number:, patches_by_file: {})
        system_prompt = File.read(@prompt_path)
        user_prompt = build_user_prompt(payload, pr_number, patches_by_file)
        content = @llm.triage(system_prompt: system_prompt, user_prompt: user_prompt)
        parse_verdict(content)
      end

      private

      def build_user_prompt(payload, pr_number, patches_by_file)
        path = payload["file_path"].to_s
        snippet = ""
        if File.file?(path)
          lines = File.readlines(path)
          snippet = lines.first(200).join
        end

        patch = patches_by_file[path].to_s
        patch = patch.byteslice(0, 24_000) if patch.bytesize > 24_000

        JSON.pretty_generate(
          pull_request: pr_number,
          finding: payload,
          diff_hunk_for_file: patch,
          current_file_excerpt: snippet
        )
      end

      def parse_verdict(content)
        raw = strip_code_fences(content)
        data = JSON.parse(raw)
        {
          "verdict" => normalize_verdict(data["verdict"]),
          "explanation" => data["explanation"].to_s,
          "criteria_results" => Array(data["criteria_results"])
        }
      rescue JSON::ParserError => e
        {
          "verdict" => "fail",
          "explanation" => "Unable to parse LLM verification JSON: #{e.message}",
          "criteria_results" => []
        }
      end

      def normalize_verdict(value)
        v = value.to_s.downcase
        return v if %w[pass fail partial].include?(v)

        "fail"
      end

      def strip_code_fences(content)
        content.gsub(/\A```(?:json)?\s*/m, "").gsub(/\s*```\z/m, "").strip
      end
    end
  end
end
