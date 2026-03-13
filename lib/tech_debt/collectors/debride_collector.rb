# frozen_string_literal: true

require "open3"
require "shellwords"
require_relative "base_collector"

module TechDebt
  module Collectors
    class DebrideCollector < BaseCollector
      def call
        return [] unless debt_type_enabled?("dead_code")

        targets = target_files
        return [] if targets.empty?

        stdout, stderr, status = Open3.capture3("bundle exec debride #{targets.map { |path| Shellwords.escape(path) }.join(' ')}")
        output = [stdout, stderr].join("\n")
        return [] if output.strip.empty?

        parse_output(output).tap do
          warn("Debride exited non-zero: #{status.exitstatus}") unless status.success?
        end
      end

      private

      def debt_type_enabled?(type)
        config.analysis.dig("debt_types", type, "enabled") == true
      end

      def target_files
        included = config.analysis.fetch("paths", []).flat_map { |pattern| Dir.glob(pattern) }
        excluded = config.analysis.fetch("exclude_paths", []).flat_map { |pattern| Dir.glob(pattern) }
        (included - excluded).uniq.select { |path| path.end_with?(".rb") && File.file?(path) }
      end

      def parse_output(output)
        output.each_line.filter_map do |line|
          # Example line:
          # app/models/user.rb:42 User#unused_method is not called from anywhere
          match = line.match(%r{^(?<file>[^:]+):(?<line>\d+)\s+(?<identifier>\S+)\s+is not called from anywhere})
          next unless match

          {
            file: match[:file],
            identifier: match[:identifier],
            type: "dead_code",
            detail: "Method appears to be uncalled (debride)",
            score: 1
          }
        end
      end
    end
  end
end
