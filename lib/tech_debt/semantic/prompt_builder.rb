# frozen_string_literal: true

require "json"

module TechDebt
  module Semantic
    class PromptBuilder
      def initialize(candidates:, max_snippet_lines: 160)
        @candidates = candidates
        @max_snippet_lines = max_snippet_lines
      end

      def build
        payload = {
          instruction: "Analyze the candidate signals and code snippets. Return only JSON array using the required schema.",
          candidates: @candidates,
          code_snippets: snippets
        }

        JSON.pretty_generate(payload)
      end

      private

      def snippets
        files = @candidates.map { |c| c[:file] }.uniq.compact.reject { |file| file == "unknown" }
        files.each_with_object({}) do |file, memo|
          next unless File.file?(file)

          memo[file] = File.readlines(file).first(@max_snippet_lines).join
        end
      end
    end
  end
end
