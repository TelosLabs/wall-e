# frozen_string_literal: true

module TechDebt
  module Collectors
    class BaseCollector
      attr_reader :config

      def initialize(config, files: nil)
        @config = config
        @explicit_files = files
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      protected

      def target_files
        if @explicit_files
          Array(@explicit_files).map(&:to_s).uniq.select { |path| path.end_with?(".rb") && File.file?(path) }
        else
          globs_from_config
        end
      end

      def globs_from_config
        included = config.analysis.fetch("paths", []).flat_map { |pattern| Dir.glob(pattern) }
        excluded = config.analysis.fetch("exclude_paths", []).flat_map { |pattern| Dir.glob(pattern) }
        (included - excluded).uniq.select { |path| path.end_with?(".rb") && File.file?(path) }
      end
    end
  end
end
