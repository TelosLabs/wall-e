# frozen_string_literal: true

require "digest"

module TechDebt
  module Github
    module Fingerprint
      module_function

      COMMENT_PREFIX = "tech_debt_fingerprint:"

      def for_item(item)
        if item["debt_type"] == "semantic_duplication" && item["canonical_pattern"] && !item["canonical_pattern"].empty?
          Digest::SHA1.hexdigest("#{item['canonical_pattern']}::semantic_duplication")
        else
          Digest::SHA1.hexdigest("#{item['file_path']}::#{item['identifier']}::#{item['debt_type']}")
        end
      end

      def to_html_comment(fingerprint)
        "<!-- #{COMMENT_PREFIX}#{fingerprint} -->"
      end
    end
  end
end
