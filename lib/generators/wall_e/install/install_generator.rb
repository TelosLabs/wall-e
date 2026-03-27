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

      def copy_verify_workflow
        say "Adding PR verification workflow...", :green
        copy_file "wall_e_verify.yml", ".github/workflows/wall_e_verify.yml"
      end

      def copy_config
        say "Adding wall-e settings...", :green
        copy_file "wall_e_settings.yml", "config/wall_e_settings.yml"
      end

      def copy_prompt
        say "Adding semantic analysis prompt...", :green
        copy_file "wall_e_analysis.md", ".github/prompts/wall_e_analysis.md"
      end

      def copy_issue_writer_prompt
        say "Adding issue writer prompt...", :green
        copy_file "wall_e_issue_writer.md", ".github/prompts/wall_e_issue_writer.md"
      end

      def copy_verification_prompt
        say "Adding PR verification prompt...", :green
        copy_file "wall_e_verification.md", ".github/prompts/wall_e_verification.md"
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
        say "  2. (Optional) Add AGENT_ASSIGN_TOKEN for auto-assign (falls back to GITHUB_TOKEN)"
        say "  3. Review .github/workflows/wall_e_scan.yml and wall_e_verify.yml triggers"
        say "  4. Adjust analysis.paths and flog_threshold in config/wall_e_settings.yml if needed"
        say "  5. Optional: set verification.close_on_pass in config/wall_e_settings.yml"
        say "  6. Test locally:"
        say "     bundle exec wall-e --dry-run --skip-llm"
        say ""
      end
    end
  end
end
