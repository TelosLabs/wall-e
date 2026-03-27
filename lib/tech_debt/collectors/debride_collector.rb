# frozen_string_literal: true

require "open3"
require "shellwords"
require_relative "base_collector"

module TechDebt
  module Collectors
    class DebrideCollector < BaseCollector
      def call
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
