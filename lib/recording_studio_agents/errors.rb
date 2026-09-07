# frozen_string_literal: true

module RecordingStudioAgents
  class Error < StandardError
  end

  class ConfigurationError < Error
  end

  class ContractError < Error
  end

  class AgentDisabled < Error
    attr_reader :key, :version

    def initialize(key, version)
      @key = key.to_s
      @version = version
      super("Agent #{key} version #{version} is disabled")
    end
  end

  class IdempotencyConflict < Error
  end

  class InvalidTransition < Error
  end

  class ExecutionFailed < Error
    attr_reader :result

    def initialize(result)
      @result = result
      message = result.respond_to?(:failure) ? result.failure.message : result.to_s
      super(message)
    end
  end
end
