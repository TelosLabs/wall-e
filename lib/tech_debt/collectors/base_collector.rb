# frozen_string_literal: true

module TechDebt
  module Collectors
    class BaseCollector
      attr_reader :config

      def initialize(config)
        @config = config
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end
    end
  end
end
