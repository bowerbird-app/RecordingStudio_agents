# frozen_string_literal: true

require "recording_studio_agents/mcp/client_claims"

module RecordingStudioAgents
  module Mcp
    class InstructionsContract < RecordingStudioApi::ActionInputContract
      def call(raw_params)
        params = ClientClaims.strip(raw_params)
        check_instructions!(params)
        super(params)
      end

      def as_json(*)
        copy = super.deep_dup
        field = copy.dig(:fields, :instructions)
        field[:maxLength] = instruction_limit if field.is_a?(Hash)
        copy
      end

      private

      def check_instructions!(raw_params)
        value = sent_instructions(raw_params)
        return if value.nil?
        raise invalid_instructions("instructions must be a string") unless value.is_a?(String)

        text = value.strip
        return if text.empty? || text.length <= instruction_limit

        raise invalid_instructions(length_message)
      end

      def sent_instructions(raw_params)
        return unless raw_params.respond_to?(:to_h)

        params = raw_params.to_h
        return params[:instructions] if params.key?(:instructions)
        return params["instructions"] if params.key?("instructions")

        nil
      end

      def instruction_limit
        RecordingStudioAgents.configuration.max_instructions_length
      end

      def length_message
        "instructions must be at most #{instruction_limit} characters"
      end

      def invalid_instructions(message)
        RecordingStudioApi::InvalidActionInputError.new(message)
      end
    end
  end
end
