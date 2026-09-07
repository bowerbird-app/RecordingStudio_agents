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
    RecordingStudioAI.stub(:generate, lambda { |**_kwargs|
      run = RecordingStudioAgents::AgentRun.last
      context = Struct.new(:run).new(
        Struct.new(:id, :request_id, :metadata).new(
          77,
          RecordingStudioAgents::Ai.request_id_for(run),
          { "agent_run_id" => run.id }
        )
      )
      RecordingStudioAgents::Handoffs::Tool.call(
        { "target_agent_key" => "reviewer", "target_agent_version" => 1 },
        context
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
end
