# frozen_string_literal: true

module RecordingStudioAgents
  module Ai
    REQUEST_ID_PREFIX = "recording-studio-agents:"

    module_function

    def request_id_for(run)
      "#{REQUEST_ID_PREFIX}#{run.id}"
    end

    def authorize!(request:, program:)
      RecordingStudioAI::Authorization.authorize!(
        :execute,
        attribution: attribution_for(request),
        context: {
          operation: "agent_run",
          agent_key: program.key,
          agent_version: program.version
        }
      )
    end

    def generate(invocation:, run:, lease_token:)
      RecordingStudioAI.generate(
        prompt: invocation.goal,
        system_instruction: invocation.system_instruction,
        custom_tools: invocation.tool_references.map do |reference|
          { key: reference.key.to_sym, version: reference.version }
        end,
        purpose: invocation.purpose,
        profile: :medium,
        root_recording: invocation.root_recording,
        context_recording: invocation.context_recording,
        initiator: invocation.initiator,
        initiator_kind: invocation.initiator_kind,
        executor: invocation.executor,
        execution_source: invocation.execution_source,
        request_id: request_id_for(run),
        metadata: {
          "agent_run_id" => run.id,
          "lease_token" => lease_token
        }
      )
    end

    def find_run(request_id:)
      return unless defined?(RecordingStudioAI::Run)

      RecordingStudioAI::Run.find_by(request_id: request_id)
    rescue StandardError
      nil
    end

    def retained_output(ai_run:, initiator:)
      retained = latest_retained_response(ai_run)
      return unless retained && initiator

      text, data = retained_text_and_data(retained, initiator)
      return if text.blank? && data.blank?

      { text: text, data: data }
    rescue StandardError
      nil
    end

    def latest_retained_response(ai_run)
      return unless ai_run.respond_to?(:attempts)

      attempt = Array(ai_run.attempts).max_by { |item| item.try(:sequence) || item.try(:id).to_i }
      attempt.response if attempt.respond_to?(:response)
    end
    private_class_method :latest_retained_response

    def retained_text_and_data(retained, initiator)
      payload = RecordingStudioAI.read_retained_response(response: retained, initiator: initiator)
      return [nil, nil] unless payload.is_a?(Hash)

      [payload[:content_text], payload[:normalized_response]]
    end
    private_class_method :retained_text_and_data

    def attribution_for(request)
      RecordingStudioAI::Contracts::Attribution.new(
        root_recording: request.root_recording,
        context_recording: request.context_recording,
        initiator: request.initiator,
        initiator_kind: request.initiator_kind,
        executor: request.executor,
        execution_source: request.execution_source
      )
    end
  end
end
