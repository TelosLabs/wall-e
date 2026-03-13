# frozen_string_literal: true

require "openai"

module TechDebt
  module Semantic
    class LlmClient
      def initialize(config)
        @config = config
      end

      def triage(system_prompt:, user_prompt:)
        key = ENV.fetch(@config.llm.fetch("api_key_env", "OPENAI_API_KEY"))
        client = OpenAI::Client.new(access_token: key)
        response = client.chat(
          parameters: {
            model: @config.llm.fetch("model"),
            temperature: @config.llm.fetch("temperature", 0.2),
            max_tokens: @config.llm.fetch("max_tokens", 4096),
            messages: [
              { role: "system", content: system_prompt },
              { role: "user", content: user_prompt }
            ]
          }
        )

        extract_content(response)
      end

      private

      def extract_content(response)
        message = response.dig("choices", 0, "message", "content")
        return message if message.is_a?(String)

        if message.is_a?(Array)
          return message.filter_map { |block| block["text"] }.join("\n")
        end

        raise "Unexpected LLM response format"
      end
    end
  end
end
