# frozen_string_literal: true

module RecordingStudioAgents
  # Popup framing origins and the host sign-in path.
  module ChatkitHostSettings
    DEFAULT_CHATKIT_ALLOWED_ORIGINS = %w[http://localhost:3000 http://127.0.0.1:3000].freeze
    FALLBACK_SIGN_IN_PATH = "/users/sign_in"

    def chatkit_allowed_origins
      return @chatkit_allowed_origins if defined?(@chatkit_allowed_origins)

      @chatkit_allowed_origins = default_chatkit_allowed_origins
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
      return @sign_in_path if defined?(@sign_in_path) && @sign_in_path.present?

      default_sign_in_path
    end

    private

    def default_chatkit_allowed_origins
      return DEFAULT_CHATKIT_ALLOWED_ORIGINS.dup if defined?(Rails) && Rails.env.local?

      []
    end

    def default_sign_in_path
      helpers = rails_url_helpers
      return helpers.new_user_session_path if helpers.respond_to?(:new_user_session_path)

      FALLBACK_SIGN_IN_PATH
    rescue NoMethodError, ArgumentError
      FALLBACK_SIGN_IN_PATH
    end

    def rails_url_helpers
      return unless defined?(Rails)

      Rails.application&.routes&.url_helpers
    end

    # Same shape as RecordingStudioEmbeddable::Floating::Origin.parse:
    # scheme, host, and a non-default port. A path or query is dropped.
    def normalize_origins(value)
      entries = value.is_a?(String) ? value.split(",") : Array(value)
      entries.flat_map { |entry| entry.to_s.split(",") }.filter_map { |entry| parse_origin(entry) }
    end

    def parse_origin(value)
      raw = value.to_s.strip
      return if raw.empty?

      origin = http_origin(raw)
      raise Error, "chatkit_allowed_origins must be http(s) origins" if origin.nil?

      origin
    end

    def http_origin(raw)
      return if raw == "*" || raw.match?(/[\s\r\n]/)

      uri = parsed_http_uri(raw)
      return if uri.nil?

      host = uri.host.downcase
      default_port = uri.scheme == "https" ? 443 : 80
      authority = uri.port == default_port ? host : "#{host}:#{uri.port}"
      "#{uri.scheme}://#{authority}"
    end

    def parsed_http_uri(raw)
      uri = URI.parse(raw)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?
      return unless %w[http https].include?(uri.scheme)

      uri
    rescue URI::InvalidURIError
      nil
    end
  end

  class Configuration
    include ChatkitHostSettings

    OVERRIDE_GATES = %i[none admin edit].freeze

    attr_accessor :instructions, :purpose, :request_actor, :request_root, :chatkit_domain_key,
                  :popup_stylesheet
    attr_reader :hooks, :default_profile, :retention_period, :provider, :instructions_override,
                :max_instructions_length, :layout, :mcp_tools

    def initialize
      assign_defaults
      @mcp_tools = :write
      @popup_stylesheet = "tailwind"
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

    def mcp_tools=(value)
      @mcp_tools = allowed_symbol(value, Mcp::ChatTools::MODES, "mcp_tools")
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
        provider: provider, mcp_tools: mcp_tools, popup_stylesheet: popup_stylesheet,
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
