# frozen_string_literal: true

require "yaml"

module TechDebt
  class Config
    REQUIRED_KEYS = %w[version llm analysis github reporting].freeze

    attr_reader :raw

    def self.load(path)
      raw = YAML.safe_load(File.read(path), aliases: true) || {}
      new(raw)
    end

    def initialize(raw)
      @raw = raw
      validate!
    end

    def llm
      raw.fetch("llm")
    end

    def analysis
      raw.fetch("analysis")
    end

    def github
      raw.fetch("github")
    end

    def reporting
      raw.fetch("reporting")
    end

    private

    def validate!
      missing = REQUIRED_KEYS.reject { |key| raw.key?(key) }
      return if missing.empty?

      raise ArgumentError, "Missing config keys: #{missing.join(', ')}"
    end
  end
end
