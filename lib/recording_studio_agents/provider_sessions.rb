# frozen_string_literal: true

module RecordingStudioAgents
  # Builds the provider handle Recording Studio AI already knows how to run.
  module ProviderSessions
    module_function

    def handle(binding_record, recordable)
      RecordingStudioAI::Agents::Session.new(
        provider: binding_record.provider,
        provider_session_id: binding_record.provider_session_id,
        model: recordable.model,
        profile: recordable.profile,
        status: recordable.status
      )
    end

    def attribution(root_recording:, initiator:, context_recording: nil, execution_source: nil)
      {
        root_recording: root_recording,
        context_recording: context_recording,
        initiator: initiator,
        execution_source: execution_source
      }.compact
    end

    def gone?(error)
      return false unless error.is_a?(RecordingStudioAI::Agents::Failure)

      normalized = error.error
      category = normalized.respond_to?(:category) ? normalized.category.to_s : ""
      code = normalized.respond_to?(:code) ? normalized.code.to_s : ""
      category == "invalid_session" || code.match?(/invalid_session|not_found|http_404/)
    end
  end
end
