# frozen_string_literal: true

require "open3"
require "shellwords"
require_relative "base_collector"

module TechDebt
  module Collectors
    class FlayCollector < BaseCollector
      def call
        targets = target_files
        return [] if targets.empty?

        threshold = config.flay_threshold
        stdout, stderr, status = Open3.capture3(
          "bundle exec flay --mass #{threshold.to_i} #{targets.map { |p| Shellwords.escape(p) }.join(' ')}"
        )
        output = [stdout, stderr].join("\n")
        return [] if output.strip.empty?

        warn("Flay exited non-zero: #{status.exitstatus}") unless status.success?
        parse_output(output, targets)
      end

      private

      def parse_output(output, targets)
        target_set = targets.map { |p| File.expand_path(p) }.to_set
        groups = split_into_groups(output)
        groups.flat_map { |group| candidates_for_group(group, target_set) }
      end

      # Split flay output into individual duplication groups.
      # Each group starts with a numbered header line.
      def split_into_groups(output)
        groups = []
        current = nil
        output.each_line do |line|
          if line.match?(/^\d+\)/)
            groups << current if current
            current = [line]
          elsif current
            current << line
          end
        end
        groups << current if current
        groups
      end

      # Parse a single group and emit one candidate per in-scope file location.
      def candidates_for_group(lines, target_set)
        header = lines.first.to_s.strip
        header_match = header.match(/^(\d+)\)\s+(IDENTICAL|Similar)\s+code found in\s+(\S+)\s+\(mass(?:\*(\d+))?\s*=\s*(\d+(?:\.\d+)?)\)/i)
        return [] unless header_match

        match_type   = header_match[2]           # "IDENTICAL" or "Similar"
        node_type    = header_match[3]           # e.g. ":defn"
        multiplier   = header_match[4].to_i.then { |m| m.zero? ? 1 : m }
        total_score  = header_match[5].to_f
        mass         = total_score / multiplier  # base mass of the duplicated block

        locations = extract_locations(lines)
        return [] if locations.empty?

        in_scope, out_of_scope = locations.partition do |loc|
          target_set.include?(File.expand_path(loc[:file]))
        end

        return [] if in_scope.empty?

        all_refs = locations.map { |l| "#{l[:file]}:#{l[:line]}" }

        in_scope.map do |loc|
          other_refs = all_refs.reject { |r| r == "#{loc[:file]}:#{loc[:line]}" }
          {
            file: loc[:file],
            identifier: "#{loc[:file]}:#{loc[:line]}",
            type: "structural_duplication",
            detail: build_detail(match_type, node_type, mass, other_refs),
            score: mass
          }
        end
      end

      def extract_locations(lines)
        lines.drop(1).filter_map do |line|
          # Handles both "  app/models/foo.rb:42" and "  A: app/models/foo.rb:42"
          match = line.match(%r{(?:[A-Z]:\s+)?(?<file>[\w./\-]+\.rb):(?<line>\d+)})
          next unless match

          { file: match[:file], line: match[:line].to_i }
        end
      end

      def build_detail(match_type, node_type, mass, other_refs)
        refs_str = other_refs.join(", ")
        "#{match_type} #{node_type} block (flay mass #{mass}) also found at: #{refs_str}"
      end
    end
  end
end
