# frozen_string_literal: true

require_relative "lib/wall_e/version"

Gem::Specification.new do |spec|
  spec.name = "wall-e"
  spec.version = WallE::VERSION
  spec.authors = ["Telos Labs"]
  spec.email = ["your@email.com"]

  spec.summary = "AI-powered semantic tech debt scanning for Rails projects"
  spec.description = "Detects semantic tech debt in Rails codebases, triages findings with LLMs, and manages GitHub issues with fingerprint-based idempotency."
  spec.homepage = "https://github.com/TelosLabs/wall-e"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["exe/**/*", "lib/**/*", "LICENSE.txt", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["wall-e"]
  spec.require_paths = ["lib"]

  spec.add_dependency "debride", "~> 1.12"
  spec.add_dependency "faraday-retry"
  spec.add_dependency "flog", "~> 4.8"
  spec.add_dependency "octokit", "~> 9.0"
  spec.add_dependency "railties", ">= 7.0"
  spec.add_dependency "ruby-openai", "~> 7.0"
end
