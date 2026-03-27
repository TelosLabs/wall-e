# frozen_string_literal: true

require "json"
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
        params = build_chat_parameters(system_prompt, user_prompt)
        response = with_rate_limit_retries do
          client.chat(parameters: params)
        end

        extract_content(response)
      rescue Faraday::BadRequestError => e
        warn "[wall-e] #{format_openai_client_error(e)}"
        raise
      end

      private

      def build_chat_parameters(system_prompt, user_prompt)
        llm = @config.llm
        model = llm.fetch("model")
        params = {
          model: model,
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: user_prompt }
          ]
        }

        apply_openai_output_token_param!(params, llm, model)
        apply_openai_temperature_param!(params, llm, model)

        params
      end

      # GPT-5 family chat models typically expect max_completion_tokens, not max_tokens, and may
      # reject custom temperature unless the API allows it.
      def gpt5_family_chat_model?(model)
        model.to_s.downcase.start_with?("gpt-5")
      end

      def apply_openai_output_token_param!(params, llm, model)
        if llm.key?("max_completion_tokens") && !llm["max_completion_tokens"].nil?
          params[:max_completion_tokens] = llm["max_completion_tokens"].to_i
        elsif gpt5_family_chat_model?(model)
          params[:max_completion_tokens] = llm.fetch("max_tokens", 4096).to_i
        else
          params[:max_tokens] = llm.fetch("max_tokens", 4096).to_i
        end
      end

      def apply_openai_temperature_param!(params, llm, model)
        if llm.key?("omit_temperature")
          params[:temperature] = llm.fetch("temperature", 0.2).to_f unless llm["omit_temperature"]
        elsif !gpt5_family_chat_model?(model)
          params[:temperature] = llm.fetch("temperature", 0.2).to_f
        end
      end

      def format_openai_client_error(error)
        prefix = "OpenAI API rejected the request (HTTP 400)."
        raw = extract_faraday_response_body(error.response)
        detail = extract_openai_error_message(raw)
        detail ? "#{prefix} #{detail}" : "#{prefix} #{error.message}"
      end

      def extract_faraday_response_body(response)
        return nil unless response

        if response.respond_to?(:body) && !response.body.nil?
          return response.body
        end

        response[:body] if response.respond_to?(:[])
      end

      def extract_openai_error_message(raw)
        return nil if raw.nil?

        data =
          case raw
          when String
            JSON.parse(raw)
          when Hash
            raw
          else
            nil
          end
        return data if data.is_a?(String) && !data.empty?

        return nil unless data.is_a?(Hash)

        err = data["error"]
        return err["message"] if err.is_a?(Hash) && err["message"]
        return err.to_s if err

        nil
      rescue JSON::ParserError, TypeError
        raw.is_a?(String) ? raw : nil
      end

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
