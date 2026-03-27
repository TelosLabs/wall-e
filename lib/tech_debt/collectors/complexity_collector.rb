# frozen_string_literal: true

require "open3"
require "shellwords"
require_relative "base_collector"

module TechDebt
  module Collectors
    class ComplexityCollector < BaseCollector
      def call
        targets = target_files
        return [] if targets.empty?

        threshold = config.flog_threshold
        stdout, stderr, status = Open3.capture3("bundle exec flog -a #{targets.map { |path| Shellwords.escape(path) }.join(' ')}")
        output = [stdout, stderr].join("\n")
        return [] if output.strip.empty?

        parse_output(output, threshold).tap do
          warn("Flog exited non-zero: #{status.exitstatus}") unless status.success?
        end
      end

      private

      def parse_output(output, threshold)
        output.each_line.filter_map do |line|
          # Example line:
          # 32.5: User#expensive_method app/models/user.rb:12-29
          match = line.match(/^\s*(?<score>\d+(?:\.\d+)?):\s+(?<rest>.+)$/)
          next unless match

          rest = match[:rest].strip
          next if rest.start_with?("flog ")

          score = match[:score].to_f
          next if score < threshold

          file = rest[%r{(?<path>[\w\/\.\-]+\.rb):\d+(?:-\d+)?}, :path]
          next unless file

          identifier = rest.sub(%r{\s+[\w\/\.\-]+\.rb:\d+(?:-\d+)?\s*$}, "")
          next if identifier =~ /\Amain#none\z/i

          {
            file: file,
            identifier: identifier,
            type: "high_complexity",
            detail: "Method complexity score #{score} exceeds threshold #{threshold}",
            score: score
          }
        end
      end
    end
  end
end
