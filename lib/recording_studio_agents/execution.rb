# frozen_string_literal: true

require_relative "skill_selection"

module RecordingStudioAgents
  module Execution
    class Request
      EXECUTION_SOURCES = RecordingStudioAI::Contracts::Attribution::EXECUTION_SOURCES
      INITIATOR_KINDS = RecordingStudioAI::Contracts::Attribution::INITIATOR_KINDS

      attr_reader :task_input, :root_recording, :context_recording, :initiator,
                  :initiator_kind, :executor, :execution_source, :idempotency_key,
                  :selection

      def self.parse(
        task:,
        root_recording:,
        initiator:,
        execution_source:,
        idempotency_key:,
        context_recording: nil,
        initiator_kind: :user,
        executor: nil,
        selection: SkillSelection.none
      )
        raise ContractError, "task is required" if task.nil?
        raise ContractError, "root_recording is required" if root_recording.nil?
        raise ContractError, "initiator is required" if initiator.nil?
        raise ContractError, "idempotency_key is required" if idempotency_key.to_s.strip.empty?

        source = execution_source.to_s
        unless EXECUTION_SOURCES.include?(source)
          raise ContractError, "execution_source must be one of: #{EXECUTION_SOURCES.join(', ')}"
        end

        kind = (initiator_kind || :user).to_s
        unless INITIATOR_KINDS.include?(kind)
          raise ContractError, "initiator_kind must be one of: #{INITIATOR_KINDS.join(', ')}"
        end

        unless context_recording.nil? || RootBoundary.contained?(context_recording, root_recording)
          raise ContractError, "context_recording must stay inside the task root"
        end

        new(
          task_input: task,
          root_recording: root_recording,
          context_recording: context_recording,
          initiator: initiator,
          initiator_kind: kind,
          executor: executor,
          execution_source: source,
          idempotency_key: idempotency_key.to_s,
          selection: selection || SkillSelection.none
        )
      end

      def initialize(
        task_input:,
        root_recording:,
        context_recording:,
        initiator:,
        initiator_kind:,
        executor:,
        execution_source:,
        idempotency_key:,
        selection: SkillSelection.none
      )
        @task_input = task_input
        @root_recording = root_recording
        @context_recording = context_recording
        @initiator = initiator
        @initiator_kind = initiator_kind
        @executor = executor
        @execution_source = execution_source
        @idempotency_key = idempotency_key
        @selection = selection || SkillSelection.none
      end
    end

    class Invocation
      attr_reader :goal, :system_instruction, :knowledge_entries, :tool_references,
                  :root_recording, :context_recording, :initiator, :initiator_kind,
                  :executor, :execution_source, :agent_run_id, :program_digest, :purpose

      def initialize(
        goal:,
        system_instruction:,
        knowledge_entries:,
        tool_references:,
        root_recording:,
        context_recording:,
        initiator:,
        initiator_kind:,
        executor:,
        execution_source:,
        agent_run_id:,
        program_digest:,
        purpose:
      )
        @goal = goal
        @system_instruction = system_instruction
        @knowledge_entries = Array(knowledge_entries)
        @tool_references = Array(tool_references)
        @root_recording = root_recording
        @context_recording = context_recording
        @initiator = initiator
        @initiator_kind = initiator_kind
        @executor = executor
        @execution_source = execution_source
        @agent_run_id = agent_run_id
        @program_digest = program_digest
        @purpose = purpose
      end
    end

    class Engine
      def initialize(program:, ledger: Persistence::RunLedger.new)
        @program = program
        @ledger = ledger
      end

      def call(request:)
        Ai.authorize!(request: request, program: @program)
        Handoffs::Tool.register! if @program.handoff_references.any?

        opening = @ledger.open!(program: @program, request: request)
        return terminal_result(opening.run) if opening.existing?

        if opening.in_progress?
          return Results::Blocked.new(run: opening.run) if opening.run.status == "awaiting_confirmation"

          return Results::InProgress.new(run: opening.run)
        end

        run = opening.run
        lease_token = opening.lease_token
        execute_acquired(request, run, lease_token)
      end

      AdoptedAi = Struct.new(:run) do
        def text
          nil
        end

        def structured_data
          nil
        end

        def citations
          []
        end

        def custom_tool_invocations
          []
        end

        def error
          status = run.respond_to?(:status) ? run.status.to_s : nil
          return if status == "completed"

          Failure.new(
            category: "provider_error",
            code: status || "generation_failed",
            message: "Adopted AI run ended as #{status}",
            retryable: status != "cancelled"
          )
        end

        def success?
          error.nil?
        end
      end

      private

      def execute_acquired(request, run, lease_token)
        invocation = @program.compose(task: request.task_input, request: request, run: run)
        @ledger.record_composed!(
          run: run,
          lease_token: lease_token,
          program: @program,
          knowledge_entries: invocation.knowledge_entries
        )

        adopted = adopt_existing_ai_run(run, lease_token)
        return adopted if adopted.is_a?(Results::InProgress) || adopted.is_a?(Results::Existing)

        response = adopted || Ai.generate(invocation: invocation, run: run, lease_token: lease_token)
        attach_response_run(run, lease_token, response)
        commit_response(run, lease_token, response)
      rescue RecordingStudioAI::Errors::ContractValidationError => e
        handle_ai_contract_error(run, lease_token, e)
      rescue StandardError => e
        failure = Failure.new(
          category: "internal",
          code: e.class.name,
          message: e.message,
          retryable: true
        )
        @ledger.commit_failed!(run: run, lease_token: lease_token, failure: failure)
        Results::Failed.new(run: run.reload, failure: failure)
      end

      def adopt_existing_ai_run(run, _lease_token)
        ai_run = Ai.find_run(request_id: Ai.request_id_for(run))
        return unless ai_run
        return unless ai_run.status.to_s == "completed"

        AdoptedAi.new(ai_run)
      end

      def terminal_result(run)
        return handoff_result(run) if run.status == "handoff_requested"

        Results::Existing.new(run: run)
      end

      def handoff_result(run)
        target = Reference.new(key: run.handoff_agent_key, version: run.handoff_agent_version)
        Results::HandoffRequested.new(run: run, request: HandoffRequest.new(target: target))
      end

      def attach_response_run(run, lease_token, response)
        ai_run = response.respond_to?(:run) ? response.run : nil
        @ledger.attach_ai_run!(run: run, lease_token: lease_token, ai_run: ai_run) if ai_run
      end

      def commit_response(run, lease_token, response)
        run.reload
        if run.handoff_agent_key.present?
          target = Reference.new(key: run.handoff_agent_key, version: run.handoff_agent_version)
          @ledger.commit_handoff!(run: run, lease_token: lease_token, target: target)
          return handoff_result(run.reload)
        end

        if blocked?(response)
          @ledger.commit_blocked!(run: run, lease_token: lease_token)
          return Results::Blocked.new(run: run.reload)
        end

        unless successful?(response)
          failure = failure_from(response)
          @ledger.commit_failed!(run: run, lease_token: lease_token, failure: failure)
          return Results::Failed.new(run: run.reload, failure: failure)
        end

        digest = Digests.output_from(response)
        @ledger.commit_succeeded!(run: run, lease_token: lease_token, digest: digest)
        Results::Completed.new(run: run.reload, output: output_from(response))
      end

      def handle_ai_contract_error(run, lease_token, error)
        if confirmation_pending?(error)
          @ledger.commit_blocked!(run: run, lease_token: lease_token)
          return Results::Blocked.new(run: run.reload)
        end

        failure = Failure.new(
          category: error.code == "authorization" ? "authorization" : "invalid_request",
          code: error.code,
          message: error.message,
          retryable: false
        )
        @ledger.commit_failed!(run: run, lease_token: lease_token, failure: failure)
        Results::Failed.new(run: run.reload, failure: failure)
      end

      def blocked?(response)
        error = response.respond_to?(:error) ? response.error : nil
        return true if error && %w[custom_tool_confirmation_required].include?(error.category)
        return true if error && error.code.to_s.include?("confirmation_pending")

        invocations = response.respond_to?(:custom_tool_invocations) ? Array(response.custom_tool_invocations) : []
        invocations.any? do |item|
          status = item.respond_to?(:[]) ? item[:status] || item["status"] : item.try(:status)
          status.to_s == "awaiting_confirmation"
        end
      end

      def confirmation_pending?(error)
        error.code.to_s.include?("confirmation_pending") ||
          error.code.to_s == "custom_tool_confirmation_required"
      end

      def successful?(response)
        return false if response.respond_to?(:error) && response.error
        return response.success? if response.respond_to?(:success?)

        true
      end

      def failure_from(response)
        error = response.respond_to?(:error) ? response.error : nil
        Failure.new(
          category: error&.category || "provider_error",
          code: error&.code || "generation_failed",
          message: error&.message || "Generation failed",
          retryable: error.respond_to?(:retryable?) ? error.retryable? : true
        )
      end

      def output_from(response)
        citations = Array(response.try(:citations)).filter_map do |item|
          title = item.respond_to?(:title) ? item.title : item["title"]
          url = item.respond_to?(:url) ? item.url : item["url"]
          next if title.blank? && url.blank?

          Citation.new(title: title, url: url)
        end
        Output.new(
          text: response.try(:text),
          data: response.try(:structured_data),
          citations: citations
        )
      end
    end
  end
end
