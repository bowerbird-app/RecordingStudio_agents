# frozen_string_literal: true

require "test_helper"

class LedgerTest < PersistenceTestCase
  def test_required_idempotency_key
    register_librarian
    error = assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: " "
      )
    end
    assert_match(/idempotency_key/, error.message)
  end

  def test_duplicate_key_returns_existing_after_success
    register_librarian
    first = nil
    RecordingStudioAI.stub(:generate, generation_response) do
      first = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-1"
      )
    end
    assert_instance_of RecordingStudioAgents::Results::Completed, first

    generate_called = false
    RecordingStudioAI.stub(:generate, lambda { |**|
      generate_called = true
      generation_response
    }) do
      second = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-1"
      )
      assert_instance_of RecordingStudioAgents::Results::Existing, second
      assert_equal first.run.id, second.run.id
    end
    refute generate_called
  end

  def test_in_progress_lease_does_not_generate_again
    register_librarian
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-lease"
      )
    end
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "job-lease")
    run.update!(
      status: "running",
      lease_token: "held",
      lease_expires_at: 5.minutes.from_now,
      completed_at: nil
    )

    generate_called = false
    RecordingStudioAI.stub(:generate, lambda { |**|
      generate_called = true
      generation_response
    }) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-lease"
      )
      assert_instance_of RecordingStudioAgents::Results::InProgress, result
    end
    refute generate_called
  end

  def test_task_digest_conflict
    register_librarian
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input(goal: "Find Getting Started."),
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-a"
      )
    end

    error = assert_raises(RecordingStudioAgents::IdempotencyConflict) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input(goal: "Find a different page."),
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-b"
      )
    end
    assert_match(/different goal/, error.message)
  end

  def test_task_keeps_goal_and_drops_context_json
    register_librarian
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-task-columns"
      )
    end

    task = RecordingStudioAgents::Task.find_by!(task_key: "find_page")
    assert_equal "Find Getting Started.", task.goal
    refute_includes RecordingStudioAgents::Task.column_names, "context_json"
  end

  def test_evaluation_is_idempotent_per_evaluator
    register_librarian
    result = nil
    RecordingStudioAI.stub(:generate, generation_response) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-eval"
      )
    end
    evaluation = result.run.record_evaluation(
      evaluator: actor,
      evaluator_key: :spot_check,
      evaluator_version: 1,
      idempotency_key: "eval-1",
      verdict: "passed",
      score: 1
    )
    assert_equal "passed", evaluation.verdict
    assert_raises(ActiveRecord::RecordNotUnique) do
      result.run.record_evaluation(
        evaluator: actor,
        evaluator_key: :spot_check,
        evaluator_version: 1,
        idempotency_key: "eval-1",
        verdict: "failed"
      )
    end
  end

  def test_activity_rejects_extra_keys
    register_librarian
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-activity"
      )
    end
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "job-activity")
    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents::Persistence::RunLedger.new.append_activity!(
        run,
        "handoff_requested",
        { "target_agent_key" => "reviewer", "target_agent_version" => 1, "summary" => "nope" }
      )
    end
    assert_match(/extra keys/, error.message)
  end

  def test_expired_lease_reconciles_completed_ai_run
    register_librarian
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-reconcile"
      )
    end
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "job-reconcile")
    run.update!(
      status: "running",
      lease_token: nil,
      lease_expires_at: 1.hour.ago,
      completed_at: nil
    )

    generate_called = false
    result = nil
    completed = Struct.new(:id, :status).new(41, "completed")
    RecordingStudioAgents::Ai.stub(:find_run, completed) do
      RecordingStudioAI.stub(:generate, lambda { |**|
        generate_called = true
        generation_response
      }) do
        result = RecordingStudioAgents.agent(:librarian, version: 1).run(
          task: task_input,
          root_recording: root,
          initiator: actor,
          execution_source: :job,
          idempotency_key: "job-reconcile"
        )
      end
    end

    refute generate_called
    assert_instance_of RecordingStudioAgents::Results::Existing, result
    assert_equal "succeeded", result.run.status
  end

  def test_cancelled_run_replays_as_existing
    register_librarian
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-cancelled"
      )
    end
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "job-cancelled")
    run.update!(status: "cancelled", lease_token: nil, lease_expires_at: nil)

    generate_called = false
    result = nil
    RecordingStudioAI.stub(:generate, lambda { |**|
      generate_called = true
      generation_response
    }) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-cancelled"
      )
    end

    refute generate_called
    assert_instance_of RecordingStudioAgents::Results::Existing, result
    assert_equal "cancelled", result.run.status
  end
end
