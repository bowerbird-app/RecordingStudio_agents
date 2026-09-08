# frozen_string_literal: true

module RecordingStudioAgents
  module Handoffs
    INTERNAL_TOOL_KEY = :recording_studio_agents_request_handoff
    INTERNAL_TOOL_VERSION = 1

    class Tool
      def self.register!
        return unless defined?(RecordingStudioAI)

        RecordingStudioAI.tools.register(
          override: true,
          key: INTERNAL_TOOL_KEY,
          version: INTERNAL_TOOL_VERSION,
          name: "Request handoff",
          description: "Record an allowlisted handoff request. Do not start the target agent.",
          use_when: "The current agent cannot finish the task and an allowed target should take over.",
          do_not_use_when: "The current agent can finish the task, or the target is not in the allowlist.",
          parameters: [
            {
              name: "target_agent_key",
              type: "string",
              required: true,
              description: "Registry key of the allowed target agent."
            },
            {
              name: "target_agent_version",
              type: "integer",
              required: true,
              description: "Exact version of the allowed target agent."
            }
          ],
          returns: "Confirmation that the request was recorded.",
          cost: :low,
          latency: :instant,
          read_only: false,
          destructive: false,
          requires_confirmation: false,
          idempotent: true,
          executor_label: "RecordingStudioAgents::Handoffs::Tool",
          executor: method(:call)
        )
      end

      def self.call(arguments, ai_context)
        run = resolve_agent_run!(ai_context)
        program = Programs::Compiler.compile(
          definition: RecordingStudioAgents.agents.fetch(run.agent_key, version: run.agent_version)
        )
        target_key = arguments.fetch("target_agent_key")
        target_version = arguments.fetch("target_agent_version")
        unless program.allows_handoff?(target_key, target_version)
          raise RecordingStudioAI::Errors::ContractValidationError.new(
            "handoff target #{target_key} version #{target_version} is not allowlisted",
            code: "custom_tool_validation"
          )
        end

        begin
          Persistence::RunLedger.new.note_handoff!(
            agent_run_id: run.id,
            ai_run_id: ai_run_id(ai_context),
            target: Reference.new(key: target_key, version: target_version),
            lease_token: lease_token_for(ai_context)
          )
        rescue IdempotencyConflict
          raise RecordingStudioAI::Errors::ContractValidationError.new(
            "handoff tool could not record the request",
            code: "custom_tool_validation"
          )
        end
        {
          "recorded" => true,
          "target_agent_key" => target_key.to_s,
          "target_agent_version" => Integer(target_version)
        }
      end

      def self.resolve_agent_run!(ai_context)
        ai_run = ai_context.respond_to?(:run) ? ai_context.run : nil
        request_id = ai_run.respond_to?(:request_id) ? ai_run.request_id : nil
        agent_run_id = if request_id.to_s.start_with?(Ai::REQUEST_ID_PREFIX)
                         request_id.delete_prefix(Ai::REQUEST_ID_PREFIX)
                       end
        agent_run_id ||= metadata_agent_run_id(ai_run)
        run = AgentRun.find_by(id: agent_run_id) if agent_run_id
        return run if run

        raise RecordingStudioAI::Errors::ContractValidationError.new(
          "handoff tool could not resolve the agent run",
          code: "custom_tool_validation"
        )
      end
      private_class_method :resolve_agent_run!

      def self.metadata_agent_run_id(ai_run)
        return unless ai_run.respond_to?(:metadata)

        ai_run.metadata&.[]("agent_run_id") || ai_run.metadata&.[](:agent_run_id)
      end
      private_class_method :metadata_agent_run_id

      def self.ai_run_id(ai_context)
        ai_run = ai_context.respond_to?(:run) ? ai_context.run : nil
        ai_run.respond_to?(:id) ? ai_run.id : nil
      end
      private_class_method :ai_run_id

      def self.lease_token_for(ai_context)
        ai_run = ai_context.respond_to?(:run) ? ai_context.run : nil
        metadata = ai_run.respond_to?(:metadata) ? ai_run.metadata : nil
        token = metadata&.[]("lease_token") || metadata&.[](:lease_token)
        return token.to_s if token.to_s.strip.present?

        raise RecordingStudioAI::Errors::ContractValidationError.new(
          "handoff tool could not prove a live lease",
          code: "custom_tool_validation"
        )
      end
      private_class_method :lease_token_for
    end
  end
end
