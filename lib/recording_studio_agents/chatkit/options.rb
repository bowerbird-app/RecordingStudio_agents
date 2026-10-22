# frozen_string_literal: true

require "active_support/core_ext/hash/deep_merge"
require "active_support/core_ext/hash/keys"

module RecordingStudioAgents
  module ChatKit
    class Options
      def self.for(controller, overrides = nil, configuration: RecordingStudioAgents.configuration)
        new(controller, overrides, configuration).to_h
      end

      def initialize(controller, overrides, configuration)
        @controller = controller
        @overrides = overrides
        @configuration = configuration
      end

      def to_h
        merged = base.deep_merge(override_hash)
        merged.delete("api")
        merged
      end

      private

      def base
        hash = configured
        hash = {} unless hash.is_a?(Hash)
        hash.deep_stringify_keys
      end

      def configured
        raw = @configuration.chatkit_options
        return {} if raw.nil?
        return call_options(raw) if raw.respond_to?(:call)

        raw
      end

      def call_options(callable)
        purpose = @configuration.purpose
        if callable.arity == 1
          callable.call(@controller)
        elsif callable.arity.zero?
          callable.call
        else
          callable.call(@controller, purpose)
        end
      end

      def override_hash
        return {} unless @overrides.is_a?(Hash)

        @overrides.deep_stringify_keys
      end
    end
  end
end
