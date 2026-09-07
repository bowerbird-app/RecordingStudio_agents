# frozen_string_literal: true

module RecordingStudioAgents
  class Reference
    KEY_PATTERN = /\A[a-z][a-z0-9_]*\z/

    attr_reader :key, :version

    def initialize(key:, version:)
      @key = key.to_s
      @version = Integer(version)
      validate!
      freeze
    end

    def ==(other)
      other.is_a?(self.class) && other.key == key && other.version == version
    end

    alias eql? ==

    def hash
      [self.class, key, version].hash
    end

    def to_h
      { key: key, version: version }
    end

    private

    def validate!
      raise ContractError, "key must be snake_case, got #{key.inspect}" unless key.match?(KEY_PATTERN)

      return if version.positive?

      raise ContractError, "version must be a positive integer"
    end
  end
end
