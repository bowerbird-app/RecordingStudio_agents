# frozen_string_literal: true

module RecordingStudioAgents
  class Configuration
    OVERRIDE_GATES = %i[none admin edit].freeze

    attr_accessor :instructions, :purpose, :request_actor, :request_root, :chatkit_domain_key
    attr_reader :hooks, :default_profile, :retention_period, :provider, :instructions_override, :max_instructions_length

    def initialize
      assign_defaults
      @hooks = RecordingStudio::Hooks.new
    end

    def provider=(value)
      @provider = value.to_s.strip.downcase.presence
    end

    def default_profile=(value)
      @default_profile = value&.to_sym
    end

    def instructions_override=(value)
      @instructions_override = allowed_symbol(value, OVERRIDE_GATES, "instructions_override")
    end

    def max_instructions_length=(value)
      length = Integer(value)
      raise Error, "max_instructions_length must be a positive integer" if length < 1

      @max_instructions_length = length
    rescue ArgumentError
      raise Error, "max_instructions_length must be a positive integer"
    end

    def retention_period=(value)
      @retention_period = normalize_retention(value)
    end

    def to_h
      {
        instructions: instructions,
        instructions_override: instructions_override,
        max_instructions_length: max_instructions_length,
        default_profile: default_profile,
        purpose: purpose,
        provider: provider,
        retention_period: retention_period,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |key, value|
        setter = "#{key}="
        public_send(setter, value) if respond_to?(setter)
      end
    end

    private

    def assign_defaults
      @instructions = "Answer in plain language."
      @instructions_override = :none
      @max_instructions_length = 4000
      @default_profile = :medium
      @purpose = "agent_chat"
      @provider = "openai"
      @retention_period = 30.days
      @request_actor = ->(*) {}
      @request_root = ->(*) {}
      @chatkit_domain_key = nil
    end

    def allowed_symbol(value, allowed, name)
      symbol = value.to_sym
      return symbol if allowed.include?(symbol)

      raise Error, "#{name} must be one of: #{allowed.join(', ')}"
    end

    def normalize_retention(value)
      return value if value.is_a?(ActiveSupport::Duration)
      return value.seconds if value.is_a?(Numeric)

      value
    end
  end
end
