# frozen_string_literal: true

require "test_helper"

class HandoffTest < PersistenceTestCase
  def setup
    super
    register_ai_tool(:find_page)
    RecordingStudioAgents.agents.register(
      key: :reviewer,
      version: 1,
      name: "Reviewer",
      description: "Reviews a miss",
      instructions: "Say what is missing."
    )
    RecordingStudioAgents.skills.register(
      key: :lookup,
      version: 1,
      name: "Lookup",
      description: "Find pages",
      instructions: "Use find_page.",
      required_tools: { find_page: 1 }
    )
    RecordingStudioAgents.agents.register(
      key: :librarian,
      version: 1,
      name: "Librarian",
      description: "Finds pages",
      instructions: "Find the named page.",
      skills: { lookup: 1 },
      tools: { find_page: 1 },
      handoffs: { reviewer: 1 }
    )
    RecordingStudioAgents::Handoffs::Tool.register!
  end

  def test_handoff_records_target_and_does_not_start_it
    result = nil
    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      RecordingStudioAgents::Handoffs::Tool.call(
        { "target_agent_key" => "reviewer", "target_agent_version" => 1 },
        ai_context_from_generate(kwargs, run_id: 77)
      )
      generation_response(text: "Need a reviewer.", run_id: 77)
    }) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "handoff-1"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::HandoffRequested, result
    assert_equal "reviewer", result.request.target.key
    assert_equal 1, result.request.target.version
    assert_equal "handoff_requested", result.run.status
    assert_equal "reviewer", result.run.handoff_agent_key
    refute_includes RecordingStudioAgents::AgentRun.column_names, "handoff_summary"
    assert_equal 0, RecordingStudioAgents::AgentRun.where(agent_key: "reviewer").count
    activity = result.run.activities.find_by(kind: "handoff_requested")
    assert_equal %w[target_agent_key target_agent_version], activity.data.keys.sort
  end

  def test_handoff_rejects_target_outside_allowlist
    register_run_then_call_tool = lambda do
      RecordingStudioAI.stub(:generate, generation_response) do
        RecordingStudioAgents.agent(:librarian, version: 1).run(
          task: task_input,
          root_recording: root,
          initiator: actor,
          execution_source: :job,
          idempotency_key: "handoff-deny"
        )
      end
    end
    register_run_then_call_tool.call
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "handoff-deny")
    context = Struct.new(:run).new(
      Struct.new(:id, :request_id, :metadata).new(
        12,
        RecordingStudioAgents::Ai.request_id_for(run),
        { "agent_run_id" => run.id }
      )
    )

    error = assert_raises(RecordingStudioAI::Errors::ContractValidationError) do
      RecordingStudioAgents::Handoffs::Tool.call(
        { "target_agent_key" => "stranger", "target_agent_version" => 1 },
        context
      )
    end
    assert_match(/not allowlisted/, error.message)
    assert_equal 0, RecordingStudioAgents::AgentRun.where(agent_key: "stranger").count
  end

  def test_handoff_without_agent_run_raises
    context = Struct.new(:run).new(
      Struct.new(:id, :request_id, :metadata).new(1, "other:1", {})
    )

    error = assert_raises(RecordingStudioAI::Errors::ContractValidationError) do
      RecordingStudioAgents::Handoffs::Tool.call(
        { "target_agent_key" => "reviewer", "target_agent_version" => 1 },
        context
      )
    end
    assert_match(/could not resolve the agent run/, error.message)
  end

  def test_replay_after_handoff_returns_the_same_request
    record_handoff!("handoff-replay")

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
        idempotency_key: "handoff-replay"
      )
    end

    refute generate_called
    assert_instance_of RecordingStudioAgents::Results::HandoffRequested, result
    assert_equal "reviewer", result.request.target.key
    assert_equal 1, result.request.target.version
    assert_equal "handoff_requested", result.run.status
  end

  def test_expired_lease_keeps_a_recorded_handoff
    record_handoff!("handoff-reconcile")
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "handoff-reconcile")
    run.update!(
      status: "running",
      lease_token: nil,
      lease_expires_at: 1.hour.ago,
      completed_at: nil
    )

    generate_called = false
    result = nil
    completed = Struct.new(:id, :status).new(77, "completed")
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
          idempotency_key: "handoff-reconcile"
        )
      end
    end

    refute generate_called
    assert_instance_of RecordingStudioAgents::Results::HandoffRequested, result
    assert_equal "handoff_requested", result.run.status
    assert_equal "reviewer", result.run.handoff_agent_key
    refute_equal "succeeded", result.run.status
  end

  def test_stale_lease_does_not_record_handoff
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "handoff-stale"
      )
    end
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "handoff-stale")
    run.update!(
      status: "running",
      lease_token: "current-lease",
      lease_expires_at: 5.minutes.from_now,
      completed_at: nil,
      handoff_agent_key: nil,
      handoff_agent_version: nil
    )

    error = assert_raises(RecordingStudioAI::Errors::ContractValidationError) do
      RecordingStudioAgents::Handoffs::Tool.call(
        { "target_agent_key" => "reviewer", "target_agent_version" => 1 },
        ai_context_for(run, lease_token: "stale-lease")
      )
    end

    assert_match(/could not record the request/, error.message)
    assert_nil run.reload.handoff_agent_key
  end

  def test_handoff_without_lease_token_raises
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "handoff-no-lease"
      )
    end
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "handoff-no-lease")
    run.update!(
      status: "running",
      lease_token: "current-lease",
      lease_expires_at: 5.minutes.from_now,
      completed_at: nil
    )

    error = assert_raises(RecordingStudioAI::Errors::ContractValidationError) do
      RecordingStudioAgents::Handoffs::Tool.call(
        { "target_agent_key" => "reviewer", "target_agent_version" => 1 },
        ai_context_for(run, lease_token: nil)
      )
    end

    assert_match(/live lease/, error.message)
    assert_nil run.reload.handoff_agent_key
  end

  private

  def record_handoff!(idempotency_key)
    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      RecordingStudioAgents::Handoffs::Tool.call(
        { "target_agent_key" => "reviewer", "target_agent_version" => 1 },
        ai_context_from_generate(kwargs, run_id: 77)
      )
      generation_response(text: "Need a reviewer.", run_id: 77)
    }) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: idempotency_key
      )
    end
  end

  def ai_context_from_generate(kwargs, run_id:)
    Struct.new(:run).new(
      Struct.new(:id, :request_id, :metadata).new(
        run_id,
        kwargs[:request_id],
        kwargs[:metadata]
      )
    )
  end

  def ai_context_for(run, lease_token:, ai_run_id: 12)
    Struct.new(:run).new(
      Struct.new(:id, :request_id, :metadata).new(
        ai_run_id,
        RecordingStudioAgents::Ai.request_id_for(run),
        { "agent_run_id" => run.id, "lease_token" => lease_token }.compact
      )
    )
  end
end
