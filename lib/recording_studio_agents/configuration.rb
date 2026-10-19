# frozen_string_literal: true

module RecordingStudioAgents
  class Configuration
    attr_accessor :instructions, :purpose, :request_actor, :request_root, :chatkit_domain_key
    attr_reader :hooks, :default_profile, :retention_period, :provider

    def initialize
      @instructions = "Answer in plain language."
      @default_profile = :medium
      @purpose = "agent_chat"
      @provider = "openai"
      @retention_period = 30.days
      @request_actor = ->(*) {}
      @request_root = ->(*) {}
      @chatkit_domain_key = nil
      @hooks = RecordingStudio::Hooks.new
    end

    def provider=(value)
      @provider = value.nil? ? nil : value.to_s.strip.downcase
    end

    def default_profile=(value)
      @default_profile = value&.to_sym
    end

    def retention_period=(value)
      @retention_period = normalize_retention(value)
    end

    def to_h
      {
        instructions: instructions,
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

    def normalize_retention(value)
      return value if value.is_a?(ActiveSupport::Duration)
      return value.seconds if value.is_a?(Numeric)

      value
    end
  end
end
