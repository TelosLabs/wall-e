# frozen_string_literal: true

require "json"
require_relative "llm_client"
require_relative "prompt_builder"

module TechDebt
  module Semantic
    class Triage
      def initialize(config, prompt_path:)
        @config = config
        @prompt_path = prompt_path
        @llm_client = LlmClient.new(config)
      end

      def call(candidates)
        system_prompt = File.read(@prompt_path)
        user_prompt = PromptBuilder.new(candidates: candidates).build
        content = @llm_client.triage(system_prompt: system_prompt, user_prompt: user_prompt)
        parse_json(content)
      end

      private

      def parse_json(content)
        raw = strip_code_fences(content)
        parsed = JSON.parse(raw)
        return parsed if parsed.is_a?(Array)

        raise "LLM response was not an array"
      rescue JSON::ParserError => e
        repaired = attempt_repair_truncated_json(raw, e)
        return repaired if repaired

        raise "Unable to parse LLM JSON response: #{e.message}"
      end

      def strip_code_fences(content)
        content.gsub(/\A```(?:json)?\s*/m, "").gsub(/\s*```\z/m, "").strip
      end

      def attempt_repair_truncated_json(raw, error)
        return nil unless error.message.include?("unexpected end of input")

        # Truncation often leaves a trailing comma or incomplete object. Try to salvage.
        # Find the last complete object (ends with "},\s*") and close the array.
        if (idx = raw.rindex(/}\s*,\s*/m))
          repaired = raw[0..idx] + "]"
          parsed = JSON.parse(repaired)
          return parsed if parsed.is_a?(Array)
        end

        # Fallback: last "}" at end of string (object boundary)
        if (idx = raw.rindex(/}\s*\z/m))
          repaired = raw[0..idx] + "]"
          parsed = JSON.parse(repaired)
          return parsed if parsed.is_a?(Array)
        end

        nil
      end
    end
  end
end
