# frozen_string_literal: true

module TechDebtCollector
  class Railtie < Rails::Railtie
    generators do
      require "generators/tech_debt_collector/install/install_generator"
    end
  end
end
