# frozen_string_literal: true

module RecordingStudioAgents
  # Popup framing origins and the host sign-in path.
  module ChatkitHostSettings
    DEFAULT_CHATKIT_ALLOWED_ORIGINS = %w[http://localhost:3000 http://127.0.0.1:3000].freeze
    DEFAULT_SIGN_IN_PATH = "/users/sign_in"
    ORIGIN_PATTERN = %r{\Ahttps?://[^/\s]+\z}i

    def chatkit_allowed_origins
      @chatkit_allowed_origins ||= DEFAULT_CHATKIT_ALLOWED_ORIGINS.dup
    end

    def chatkit_allowed_origins=(value)
      @chatkit_allowed_origins = normalize_origins(value)
    end

    def sign_in_path=(value)
      if value.nil?
        @sign_in_path = nil
        return
      end

      raise Error, "sign_in_path must be a path or a lambda" unless value.is_a?(String) || value.respond_to?(:call)

      @sign_in_path = value
    end

    def sign_in_path
      @sign_in_path.presence || DEFAULT_SIGN_IN_PATH
    end

    private

    def normalize_origins(value)
      entries = value.is_a?(String) ? value.split(",") : Array(value)
      origins = entries.flat_map { |entry| entry.to_s.split(",") }.map(&:strip).reject(&:empty?)
      origins.each do |origin|
        raise Error, "chatkit_allowed_origins must be http(s) origins" unless ORIGIN_PATTERN.match?(origin)
      end
      origins
    end
  end

  class Configuration
    include ChatkitHostSettings

    OVERRIDE_GATES = %i[none admin edit].freeze
    DEFAULT_CHATKIT_ALLOWED_ORIGINS = ChatkitHostSettings::DEFAULT_CHATKIT_ALLOWED_ORIGINS

    attr_accessor :instructions, :purpose, :request_actor, :request_root, :chatkit_domain_key
    attr_reader :hooks, :default_profile, :retention_period, :provider, :instructions_override,
                :max_instructions_length, :layout

    def initialize
      assign_defaults
      @hooks = RecordingStudio::Hooks.new
    end

    def provider=(value)
      @provider = value.to_s.strip.downcase.presence
    end

    def layout=(value)
      @layout = RecordingStudio::Layout.accept(value)
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

    def chatkit_options=(value)
      unless value.nil? || value.is_a?(Hash) || value.respond_to?(:call)
        raise Error, "chatkit_options must be a hash or a lambda"
      end
      raise Error, "chatkit_options lambda accepts 0, 1, or 2 arguments" unless options_callable?(value)

      @chatkit_options = value.nil? ? {} : value
    end

    def chatkit_options
      @chatkit_options || {}
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

    def options_callable?(value)
      return true unless value.respond_to?(:call)

      arity = value.arity
      return true if arity.between?(0, 2)
      return false if arity > 2

      (-arity - 1) <= 2
    end

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
      @chatkit_domain_key = @layout = nil
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
