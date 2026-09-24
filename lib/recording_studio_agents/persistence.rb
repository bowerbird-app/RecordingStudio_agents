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

      def blocked?
        kind == :blocked
      end
    end

    class RunLedger
      ACTIVITY_KEYS = {
        "run_created" => %w[task_id],
        "program_composed" => %w[program_digest selected_skill_keys],
        "knowledge_loaded" => %w[entry_count],
        "ai_run_linked" => %w[recording_studio_ai_run_id],
        "handoff_requested" => %w[target_agent_key target_agent_version],
        "run_succeeded" => %w[],
        "run_failed" => %w[failure_code failure_category],
        "run_cancelled" => %w[],
        "evaluation_recorded" => %w[evaluator_key verdict],
        "awaiting_confirmation" => %w[],
        "step_started" => %w[sequence action_type],
        "step_completed" => %w[sequence action_type],
        "state_updated" => %w[sequence],
        "controller_evaluated" => %w[sequence],
        "reasoner_requested" => %w[sequence],
        "replanned" => %w[sequence],
        "stuck_detected" => %w[sequence],
        "compacted" => %w[sequence]
      }.freeze

      def initialize(lease_seconds: RecordingStudioAgents.configuration.lease_seconds)
        @lease_seconds = lease_seconds
      end

      def open!(program:, request:)
        task = upsert_task!(request)
        run = find_or_insert_run!(task, program, request)

        run.with_lock do
          run.reload
          return Opening.new(kind: :existing, task: task, run: run) if Lifecycle.terminal?(run.status)
          return Opening.new(kind: :in_progress, task: task, run: run) if held_by_live_lease?(run)

          reconcile_ai_run!(run)
          run.reload
          return Opening.new(kind: :existing, task: task, run: run) if Lifecycle.terminal?(run.status)
          return Opening.new(kind: :in_progress, task: task, run: run) if held_by_live_lease?(run)
          if run.status == "awaiting_confirmation" && !recoverable_ai_run?(run) && !confirmation_step?(run)
            return Opening.new(kind: :blocked, task: task, run: run)
          end

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

      def note_handoff!(agent_run_id:, ai_run_id:, target:, lease_token:)
        if lease_token.to_s.strip.empty?
          raise IdempotencyConflict, "lease is required to record a handoff for agent run #{agent_run_id}"
        end

        run = AgentRun.find(agent_run_id)
        with_valid_lease!(run, lease_token) do |locked|
          unless locked.allows_handoff?(target.key, target.version)
            raise IdempotencyConflict, "handoff target is not allowlisted on agent run #{locked.id}"
          end

          locked.update!(
            handoff_agent_key: target.key,
            handoff_agent_version: target.version,
            recording_studio_ai_run_id: locked.recording_studio_ai_run_id || ai_run_id
          )
          unless locked.run_activities.exists?(kind: "handoff_requested")
            append_activity!(locked, "handoff_requested", {
                               "target_agent_key" => target.key,
                               "target_agent_version" => target.version
                             })
          end
        end
      end

      def record_composed!(run:, lease_token:, program:, knowledge_entries:)
        with_valid_lease!(run, lease_token) do |locked|
          return if locked.run_activities.exists?(kind: "program_composed")

          append_activity!(locked, "program_composed", {
                             "program_digest" => program.digest,
                             "selected_skill_keys" => locked.selected_skill_key_list
                           })
          append_activity!(locked, "knowledge_loaded", { "entry_count" => knowledge_entries.length })
        end
      end

      def renew_lease!(run:, lease_token:)
        with_valid_lease!(run, lease_token) do |locked|
          locked.update!(lease_expires_at: Time.current + @lease_seconds)
        end
      end

      def checkpoint!(run:, lease_token:, state:, step:, activities: [])
        with_valid_lease!(run, lease_token) do |locked|
          locked.update!(
            working_state_json: state.data,
            lease_expires_at: Time.current + @lease_seconds
          )
          saved = upsert_step!(locked, step)
          Array(activities).flatten.each do |kind|
            data = { "sequence" => saved.sequence }
            data["action_type"] = saved.action_type if ACTIVITY_KEYS.fetch(kind).include?("action_type")
            append_activity!(locked, kind, data)
          end
          saved
        end
      end

      def note_activity!(run:, lease_token:, kind:, data:)
        with_valid_lease!(run, lease_token) do |locked|
          append_activity!(locked, kind, data)
          locked.update!(lease_expires_at: Time.current + @lease_seconds)
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
          input_digest: request.task_input.digest
        }
        task = Task.find_or_initialize_by(
          root_recording_id: attributes[:root_recording_id],
          task_key: attributes[:task_key]
        )
        if task.persisted? && task.input_digest != attributes[:input_digest]
          raise IdempotencyConflict, "task #{task.task_key} already exists with a different input"
        end

        task.assign_attributes(attributes) unless task.persisted?
        task.save!
        task
      rescue ActiveRecord::RecordNotUnique
        Task.find_by!(root_recording_id: attributes[:root_recording_id], task_key: attributes[:task_key]).tap do |found|
          if found.input_digest != attributes[:input_digest]
            raise IdempotencyConflict, "task #{found.task_key} already exists with a different input"
          end
        end
      end

      def find_or_insert_run!(task, program, request)
        selection = request.selection || SkillSelection.none
        attributes = {
          task: task,
          root_recording_id: request.root_recording.id,
          context_recording_id: request.context_recording&.id,
          agent_key: program.key,
          agent_version: program.version,
          program_digest: program.digest,
          selected_skills_json: selection.as_json,
          skill_pack_key: selection.pack&.key,
          skill_pack_version: selection.pack&.version,
          handoff_allowlist_json: handoff_allowlist(program),
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
        if run
          assert_same_execution!(run, program, task, request)
          return run
        end

        run = AgentRun.create!(attributes)
        append_activity!(run, "run_created", { "task_id" => task.id })
        run
      rescue ActiveRecord::RecordNotUnique
        AgentRun.find_by!(
          root_recording_id: attributes[:root_recording_id],
          agent_key: attributes[:agent_key],
          agent_version: attributes[:agent_version],
          idempotency_key: attributes[:idempotency_key]
        ).tap { |found| assert_same_execution!(found, program, task, request) }
      end

      def assert_same_program!(run, program)
        return if run.program_digest == program.digest

        raise IdempotencyConflict,
              "idempotency_key #{run.idempotency_key} already exists with a different program"
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
        return unless run.status == "running"
        return unless run.lease_expired? || run.lease_token.blank?
        return if run.handoff_agent_key.blank?

        finish_recorded_handoff!(run)
      end

      def recoverable_ai_run?(run)
        return false if confirmation_step?(run)

        ai_run = Ai.find_run(request_id: Ai.request_id_for(run))
        return false unless ai_run.respond_to?(:status)

        ai_run.status.to_s == "completed"
      end

      def confirmation_step?(run)
        return false unless run.respond_to?(:agent_steps)

        run.agent_steps.exists?(status: "awaiting_confirmation")
      rescue StandardError
        false
      end

      def upsert_step!(run, attributes)
        attrs = attributes.symbolize_keys
        sequence = Integer(attrs.fetch(:sequence))
        step = run.agent_steps.find_by(sequence: sequence)
        now = Time.current
        payload = attrs.except(:sequence).compact
        if step
          payload[:completed_at] = now if finished_step?(payload[:status]) && step.completed_at.nil?
          step.update!(payload)
          step
        else
          run.agent_steps.create!(
            payload.merge(
              sequence: sequence,
              started_at: now,
              completed_at: finished_step?(payload[:status]) ? now : nil
            )
          )
        end
      end

      def finished_step?(status)
        %w[completed failed unresolved].include?(status.to_s)
      end

      def handoff_allowlist(program)
        program.handoff_references.map do |reference|
          { "key" => reference.key.to_s, "version" => reference.version }
        end
      end

      def assert_same_execution!(run, program, task, request)
        assert_same_program!(run, program)
        if run.task_id != task.id
          raise IdempotencyConflict,
                "idempotency_key #{run.idempotency_key} already exists for a different task"
        end
        return if run.context_recording_id.to_s == request.context_recording&.id.to_s

        raise IdempotencyConflict,
              "idempotency_key #{run.idempotency_key} already exists with a different context recording"
      end

      def finish_recorded_handoff!(run)
        Lifecycle.transition!(from: run.status, to: "handoff_requested") unless run.status == "handoff_requested"
        run.update!(
          status: "handoff_requested",
          lease_token: nil,
          lease_expires_at: nil,
          completed_at: Time.current
        )
        return if run.run_activities.exists?(kind: "handoff_requested")

        append_activity!(run, "handoff_requested", {
                           "target_agent_key" => run.handoff_agent_key,
                           "target_agent_version" => run.handoff_agent_version
                         })
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
