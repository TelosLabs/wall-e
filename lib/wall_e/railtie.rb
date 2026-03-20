# frozen_string_literal: true

module WallE
  class Railtie < Rails::Railtie
    generators do
      require "generators/wall_e/install/install_generator"
    end
  end
end
