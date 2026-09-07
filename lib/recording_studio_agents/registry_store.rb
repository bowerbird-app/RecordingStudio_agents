# frozen_string_literal: true

module RecordingStudioAgents
  module RegistryStore
    def initialize
      @definitions = {}
    end

    def fetch(key, version:)
      definition = @definitions[storage_key(key, version)]
      return definition if definition

      raise ConfigurationError, "#{self.class.name} has no #{key} version #{version}"
    end

    def all
      @definitions.values.sort_by { |definition| [definition.key, definition.version] }
    end

    def clear!
      @definitions = {}
    end

    private

    def storage_key(key, version)
      [key.to_s, Integer(version)]
    end

    def store(definition)
      key = storage_key(definition.key, definition.version)
      if @definitions.key?(key)
        raise ConfigurationError, "#{definition.key} version #{definition.version} is already registered"
      end

      @definitions[key] = definition
    end
  end
end
