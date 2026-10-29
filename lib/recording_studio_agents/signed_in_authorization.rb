# frozen_string_literal: true

module RecordingStudioAgents
  # Allows recording_studio_ai.execute for a signed-in actor. Every other
  # Recording Studio AI action stays denied. Assign it on the AI configuration:
  #
  #   config.authorization_handler = RecordingStudioAgents::SignedInAuthorization.method(:call)
  module SignedInAuthorization
    EXECUTE = "recording_studio_ai.execute"

    module_function

    def call(action:, attribution:, **)
      return false unless action.to_s == EXECUTE
      return false if attribution.nil? || attribution.initiator.blank?

      true
    end
  end
end
