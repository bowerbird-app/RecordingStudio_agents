# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # Clients may send authorized_by_* or a metadata bag on a tool call.
    # Those keys are not inputs. The server writes authorized_by itself.
    module ClientClaims
      KEYS = %i[authorized_by_type authorized_by_id].freeze

      module_function

      def strip(raw_params)
        return {} unless raw_params.respond_to?(:to_h)

        params = raw_params.to_h.symbolize_keys
        KEYS.each { |key| params.delete(key) }
        drop_metadata_claims!(params)
        params.delete(:metadata)
        params
      end

      def drop_metadata_claims!(params)
        metadata = params[:metadata]
        return unless metadata.respond_to?(:to_h) && !metadata.is_a?(String)

        cleaned = metadata.to_h.symbolize_keys
        KEYS.each { |key| cleaned.delete(key) }
        params[:metadata] = cleaned
      end
    end
  end
end
