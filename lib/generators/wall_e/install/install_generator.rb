# frozen_string_literal: true

require "rails/generators/base"

module WallE
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      namespace "wall_e:install"

      desc "Installs wall-e workflow, config, and prompt files"

      def copy_workflow
        say "Adding GitHub Action workflow...", :green
        copy_file "wall_e_scan.yml", ".github/workflows/wall_e_scan.yml"
      end

      def copy_config
        say "Adding wall-e settings...", :green
        copy_file "wall_e_settings.yml", "config/wall_e_settings.yml"
      end

      def copy_prompt
        say "Adding semantic analysis prompt...", :green
        copy_file "wall_e_analysis.md", ".github/prompts/wall_e_analysis.md"
      end

      def print_next_steps
        say ""
        say "=" * 60, :green
        say "  wall-e installed successfully!", :green
        say "=" * 60, :green
        say ""
        say "Next steps:", :yellow
        say ""
        say "  1. Add OPENAI_API_KEY as a GitHub Actions secret"
        say "  2. (Optional) Add AGENT_ASSIGN_TOKEN for auto-assign to Copilot/Cursor"
        say "  3. Review .github/workflows/wall_e_scan.yml triggers"
        say "  4. Tune config/wall_e_settings.yml thresholds if needed"
        say "  5. Test locally:"
        say "     bundle exec wall-e --dry-run --skip-llm"
        say ""
      end
    end
  end
end
