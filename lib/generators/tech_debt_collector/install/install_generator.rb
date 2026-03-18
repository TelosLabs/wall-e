# frozen_string_literal: true

require "rails/generators/base"

module TechDebtCollector
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      namespace "tech_debt_collector:install"

      desc "Installs AI tech debt collector workflow, config, and prompt files"

      def copy_workflow
        say "Adding GitHub Action workflow...", :green
        copy_file "ai_tech_debt_scan.yml", ".github/workflows/ai_tech_debt_scan.yml"
      end

      def copy_config
        say "Adding tech debt settings...", :green
        copy_file "tech_debt_settings.yml", "config/tech_debt_settings.yml"
      end

      def copy_prompt
        say "Adding semantic analysis prompt...", :green
        copy_file "tech_debt_analysis.md", ".github/prompts/tech_debt_analysis.md"
      end

      def print_next_steps
        say ""
        say "=" * 60, :green
        say "  Tech Debt Collector installed successfully!", :green
        say "=" * 60, :green
        say ""
        say "Next steps:", :yellow
        say ""
        say "  1. Add OPENAI_API_KEY as a GitHub Actions secret"
        say "  2. (Optional) Add AGENT_ASSIGN_TOKEN for auto-assign to Copilot/Cursor"
        say "  3. Review .github/workflows/ai_tech_debt_scan.yml triggers"
        say "  4. Tune config/tech_debt_settings.yml thresholds if needed"
        say "  5. Test locally:"
        say "     bundle exec tech-debt-collector --dry-run --skip-llm"
        say ""
      end
    end
  end
end
