# frozen_string_literal: true

require "openai"
require "faraday"

module TechDebt
  module Semantic
    class LlmClient
      def initialize(config)
        @config = config
      end

      def triage(system_prompt:, user_prompt:)
        key = ENV.fetch(@config.llm.fetch("api_key_env", "OPENAI_API_KEY"))
        client = OpenAI::Client.new(access_token: key)
        response = with_rate_limit_retries do
          client.chat(
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
        end

        extract_content(response)
      end

      private

      def with_rate_limit_retries
        attempts = 0

        begin
          yield
        rescue Faraday::TooManyRequestsError => error
          attempts += 1
          raise if attempts > retry_attempts

          sleep(retry_wait_seconds(error, attempts) + rand * 0.5)
          retry
        end
      end

      def retry_wait_seconds(error, attempts)
        retry_after_seconds(error) || (retry_base_delay_seconds * (2**(attempts - 1)))
      end

      def retry_after_seconds(error)
        response = error.response
        return nil unless response.is_a?(Hash)

        headers = response[:headers]
        return nil unless headers.respond_to?(:[])

        value = headers["retry-after"] || headers["Retry-After"]
        return nil if value.nil?

        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def retry_attempts
        @config.llm.fetch("retry_attempts", 3).to_i
      end

      def retry_base_delay_seconds
        @config.llm.fetch("retry_base_delay_seconds", 1.0).to_f
      end

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
