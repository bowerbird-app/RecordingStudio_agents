# frozen_string_literal: true

require "securerandom"

module RecordingStudioAgents
  module Persistence
    class Opening
      attr_reader :kind, :task, :run, :lease_token

      def initialize(kind:, task:, run:, lease_token: nil)
        @kind = kind
        @task = task
        @run = run
        @lease_token = lease_token
      end

      def acquired?
        kind == :acquired
      end

      def existing?
        kind == :existing
      end

      def in_progress?
        kind == :in_progress
      end
    end

    class RunLedger
      ACTIVITY_KEYS = {
        "run_created" => %w[task_id],
        "program_composed" => %w[program_digest],
        "knowledge_loaded" => %w[entry_count],
        "ai_run_linked" => %w[recording_studio_ai_run_id],
        "handoff_requested" => %w[target_agent_key target_agent_version],
        "run_succeeded" => %w[],
        "run_failed" => %w[failure_code failure_category],
        "run_cancelled" => %w[],
        "evaluation_recorded" => %w[evaluator_key verdict],
        "awaiting_confirmation" => %w[]
      }.freeze

      def initialize(lease_seconds: RecordingStudioAgents.configuration.lease_seconds)
        @lease_seconds = lease_seconds
      end

      def open!(program:, request:)
        task = upsert_task!(request)
        run = find_or_insert_run!(task, program, request)

        run.with_lock do
          run.reload
          return Opening.new(kind: :existing, task: task, run: run) if run.status == "succeeded"
          return Opening.new(kind: :in_progress, task: task, run: run) if held_by_live_lease?(run)

          reconcile_ai_run!(run)
          run.reload
          return Opening.new(kind: :existing, task: task, run: run) if run.status == "succeeded"
          return Opening.new(kind: :in_progress, task: task, run: run) if held_by_live_lease?(run)

          token = acquire_lease!(run, request)
          Opening.new(kind: :acquired, task: task, run: run, lease_token: token)
        end
      end

      def attach_ai_run!(run:, lease_token:, ai_run:)
        return unless ai_run.respond_to?(:id) && ai_run.id

        with_valid_lease!(run, lease_token) do |locked|
          locked.update!(recording_studio_ai_run_id: ai_run.id)
          append_activity!(locked, "ai_run_linked", { "recording_studio_ai_run_id" => ai_run.id })
        end
      end

      def note_handoff!(agent_run_id:, ai_run_id:, target:)
        run = AgentRun.lock.find(agent_run_id)
        run.update!(
          handoff_agent_key: target.key,
          handoff_agent_version: target.version,
          recording_studio_ai_run_id: run.recording_studio_ai_run_id || ai_run_id
        )
        append_activity!(run, "handoff_requested", {
                           "target_agent_key" => target.key,
                           "target_agent_version" => target.version
                         })
        run
      end

      def record_composed!(run:, lease_token:, program:, knowledge_entries:)
        with_valid_lease!(run, lease_token) do |locked|
          append_activity!(locked, "program_composed", { "program_digest" => program.digest })
          append_activity!(locked, "knowledge_loaded", { "entry_count" => knowledge_entries.length })
        end
      end

      def commit_succeeded!(run:, lease_token:, digest:)
        with_valid_lease!(run, lease_token) do |locked|
          transition!(locked, "succeeded")
          locked.update!(
            status: "succeeded",
            output_digest: digest,
            lease_token: nil,
            lease_expires_at: nil,
            completed_at: Time.current
          )
          append_activity!(locked, "run_succeeded", {})
        end
      end

      def commit_failed!(run:, lease_token:, failure:)
        with_valid_lease!(run, lease_token) do |locked|
          transition!(locked, "failed")
          locked.update!(
            status: "failed",
            failure_category: failure.category,
            failure_code: failure.code,
            failure_message: failure.message,
            failure_retryable: failure.retryable?,
            lease_token: nil,
            lease_expires_at: nil,
            completed_at: Time.current
          )
          append_activity!(locked, "run_failed", {
                             "failure_code" => failure.code,
                             "failure_category" => failure.category
                           })
        end
      end

      def commit_handoff!(run:, lease_token:, target:)
        with_valid_lease!(run, lease_token) do |locked|
          transition!(locked, "handoff_requested")
          locked.update!(
            status: "handoff_requested",
            handoff_agent_key: target.key,
            handoff_agent_version: target.version,
            lease_token: nil,
            lease_expires_at: nil,
            completed_at: Time.current
          )
          unless locked.run_activities.exists?(kind: "handoff_requested")
            append_activity!(locked, "handoff_requested", {
                               "target_agent_key" => target.key,
                               "target_agent_version" => target.version
                             })
          end
        end
      end

      def commit_blocked!(run:, lease_token:)
        with_valid_lease!(run, lease_token) do |locked|
          transition!(locked, "awaiting_confirmation")
          locked.update!(
            status: "awaiting_confirmation",
            lease_token: nil,
            lease_expires_at: nil
          )
          append_activity!(locked, "awaiting_confirmation", {})
        end
      end

      def record_evaluation!(
        run:,
        evaluator:,
        evaluator_key:,
        evaluator_version:,
        idempotency_key:,
        verdict:,
        score: nil,
        notes: nil,
        metadata: {}
      )
        evaluation = Evaluation.create!(
          agent_run: run,
          evaluator_type: evaluator&.class&.name,
          evaluator_id: evaluator.respond_to?(:id) ? evaluator.id.to_s : nil,
          evaluator_key: evaluator_key.to_s,
          evaluator_version: Integer(evaluator_version),
          idempotency_key: idempotency_key.to_s,
          verdict: verdict.to_s,
          score: score,
          notes: notes,
          metadata: metadata || {}
        )
        append_activity!(run, "evaluation_recorded", {
                           "evaluator_key" => evaluation.evaluator_key,
                           "verdict" => evaluation.verdict
                         })
        evaluation
      end

      def append_activity!(run, kind, data)
        extras = data.stringify_keys.keys - ACTIVITY_KEYS.fetch(kind)
        raise ConfigurationError, "activity #{kind} has extra keys: #{extras.join(', ')}" if extras.any?

        sequence = (run.run_activities.maximum(:sequence) || 0) + 1
        RunActivity.create!(
          agent_run: run,
          kind: kind,
          sequence: sequence,
          data: data,
          occurred_at: Time.current,
          created_at: Time.current
        )
      end

      private

      def upsert_task!(request)
        attributes = {
          root_recording_id: request.root_recording.id,
          context_recording_id: request.context_recording&.id,
          task_key: request.task_input.key,
          goal: request.task_input.goal,
          context_json: request.task_input.context,
          input_digest: request.task_input.digest
        }
        task = Task.find_or_initialize_by(
          root_recording_id: attributes[:root_recording_id],
          task_key: attributes[:task_key]
        )
        if task.persisted? && task.input_digest != attributes[:input_digest]
          raise IdempotencyConflict, "task #{task.task_key} already exists with a different goal"
        end

        task.assign_attributes(attributes) unless task.persisted?
        task.save!
        task
      rescue ActiveRecord::RecordNotUnique
        Task.find_by!(root_recording_id: attributes[:root_recording_id], task_key: attributes[:task_key]).tap do |found|
          if found.input_digest != attributes[:input_digest]
            raise IdempotencyConflict, "task #{found.task_key} already exists with a different goal"
          end
        end
      end

      def find_or_insert_run!(task, program, request)
        attributes = {
          task: task,
          root_recording_id: request.root_recording.id,
          context_recording_id: request.context_recording&.id,
          agent_key: program.key,
          agent_version: program.version,
          program_digest: program.digest,
          idempotency_key: request.idempotency_key,
          status: "pending",
          initiator_type: request.initiator.class.name,
          initiator_id: request.initiator.id.to_s,
          initiator_kind: request.initiator_kind.to_s,
          executor_type: request.executor&.class&.name,
          executor_id: request.executor.respond_to?(:id) ? request.executor.id.to_s : nil,
          execution_source: request.execution_source.to_s
        }
        run = AgentRun.find_by(
          root_recording_id: attributes[:root_recording_id],
          agent_key: attributes[:agent_key],
          agent_version: attributes[:agent_version],
          idempotency_key: attributes[:idempotency_key]
        )
        return run if run

        run = AgentRun.create!(attributes)
        append_activity!(run, "run_created", { "task_id" => task.id })
        run
      rescue ActiveRecord::RecordNotUnique
        AgentRun.find_by!(
          root_recording_id: attributes[:root_recording_id],
          agent_key: attributes[:agent_key],
          agent_version: attributes[:agent_version],
          idempotency_key: attributes[:idempotency_key]
        )
      end

      def held_by_live_lease?(run)
        run.status == "running" &&
          run.lease_token.present? &&
          !run.lease_expired?
      end

      def acquire_lease!(run, request)
        Lifecycle.transition!(from: run.status, to: "running") unless run.status == "running"
        token = SecureRandom.uuid
        run.update!(
          status: "running",
          lease_token: token,
          lease_expires_at: Time.current + @lease_seconds,
          started_at: run.started_at || Time.current,
          initiator_type: request.initiator.class.name,
          initiator_id: request.initiator.id.to_s,
          initiator_kind: request.initiator_kind.to_s,
          executor_type: request.executor&.class&.name,
          executor_id: request.executor.respond_to?(:id) ? request.executor.id.to_s : nil,
          completed_at: nil,
          failure_category: nil,
          failure_code: nil,
          failure_message: nil,
          failure_retryable: nil
        )
        token
      end

      def reconcile_ai_run!(run)
        return unless %w[running awaiting_confirmation failed].include?(run.status)
        return unless run.lease_expired? || run.lease_token.blank?

        ai_run = Ai.find_run(request_id: Ai.request_id_for(run))
        return unless ai_run

        run.update!(recording_studio_ai_run_id: ai_run.id) if run.recording_studio_ai_run_id.blank? && ai_run.id
        return unless ai_run.respond_to?(:status)

        case ai_run.status.to_s
        when "completed"
          Lifecycle.transition!(from: run.status, to: "succeeded") unless run.status == "succeeded"
          run.update!(
            status: "succeeded",
            lease_token: nil,
            lease_expires_at: nil,
            completed_at: Time.current,
            output_digest: run.output_digest || Digests.of("ai_run" => ai_run.id)
          )
          append_activity!(run, "run_succeeded", {}) unless run.run_activities.exists?(kind: "run_succeeded")
        when "failed", "cancelled"
          nil
        end
      end

      def with_valid_lease!(run, lease_token)
        run.with_lock do
          run.reload
          unless run.lease_token == lease_token && !run.lease_expired?
            raise IdempotencyConflict, "lease is no longer valid for agent run #{run.id}"
          end

          yield run
        end
      end

      def transition!(run, to)
        Lifecycle.transition!(from: run.status, to: to)
      end
    end
  end
end
