# frozen_string_literal: true

require "test_helper"

class PlaygroundStepsTest < ActiveSupport::TestCase
  Turn = PlaygroundSteps::Turn
  ToolNote = PlaygroundSteps::ToolNote

  test "each turn shows its own input and response" do
    asked = ToolNote.new(name: "Find page", key: "find_page", value: { "title" => "Staff handbook" })
    heard = ToolNote.new(name: "Find page", key: "find_page", value: { "found" => true })
    turns = [
      Turn.new(status: "completed", text: nil, error_message: nil, asked: [ asked ], heard: []),
      Turn.new(status: "completed", text: "Found the Staff handbook.", error_message: nil, asked: [], heard: [ heard ])
    ]

    entries = PlaygroundSteps.build(
      turns,
      instruction: "Find the staff handbook.",
      context: "{\"folder\":\"People\"}",
      status: "succeeded"
    )

    assert_equal [ "playground-step-0", "playground-step-1" ], entries.map(&:id)
    assert_equal "Find page", entries.first.title
    assert_equal "Done", entries.first.badge
    first = JSON.parse(entries.first.exchange)
    assert_equal(
      { "instruction" => "Find the staff handbook.", "context" => { "folder" => "People" } },
      first["input"]
    )
    assert_equal({ "find_page" => { "title" => "Staff handbook" } }, first["output"])

    assert_equal "Reply", entries.second.title
    second = JSON.parse(entries.second.exchange)
    assert_equal({ "find_page" => { "found" => true } }, second["input"])
    assert_equal({ "text" => "Found the Staff handbook." }, second["output"])
  end

  test "a running model turn is visible before the agent run links it" do
    workspace = Workspace.create!(name: "Playground Steps #{SecureRandom.hex(4)}")
    root = RecordingStudio.root_recording_for(workspace)
    user = User.create!(
      email: "playground-steps-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    task = RecordingStudioAgents::Task.create!(
      root_recording_id: root.id,
      task_key: "playground-steps:#{SecureRandom.hex(4)}",
      goal: "Find the staff handbook.",
      input_digest: "playground-steps"
    )
    run = RecordingStudioAgents::AgentRun.create!(
      task: task,
      root_recording_id: root.id,
      agent_key: "page_librarian",
      agent_version: 1,
      program_digest: "playground-steps",
      idempotency_key: "playground-steps:#{SecureRandom.uuid}",
      status: "running",
      initiator_type: "User",
      initiator_id: user.id.to_s,
      initiator_kind: "user",
      execution_source: "web"
    )
    now = Time.current
    ai_run = RecordingStudioAI::Run.create!(
      operation: "generation",
      purpose: "agent_page_librarian",
      status: "running",
      root_recording_id: root.id,
      initiator_type: "User",
      initiator_id: user.id.to_s,
      initiator_kind: "user",
      execution_source: "web",
      request_id: RecordingStudioAgents::Ai.request_id_for(run),
      started_at: now
    )
    RecordingStudioAI::Attempt.create!(
      run: ai_run,
      sequence: 1,
      kind: "primary",
      status: "running",
      started_at: now
    )

    entries = PlaygroundSteps.for(run, initiator: user)

    assert_nil run.recording_studio_ai_run_id
    assert_equal [ "On it" ], entries.map(&:title)
    assert_equal [ "Working" ], entries.map(&:badge)
    call = JSON.parse(entries.first.exchange)
    assert_equal({ "instruction" => "Find the staff handbook." }, call["input"])
    assert_nil call["output"]
  end

  test "a blank run has no collapses" do
    entries = PlaygroundSteps.build([], instruction: "", status: "running")

    assert_empty entries
  end

  test "a failed run with no turns shows the failure" do
    entries = PlaygroundSteps.build(
      [],
      failure_message: "The title was not saved.",
      instruction: "Rename the page.",
      status: "failed"
    )

    assert_equal [ "playground-step-0" ], entries.map(&:id)
    assert_equal "Did not finish", entries.first.title
    call = JSON.parse(entries.first.exchange)
    assert_equal({ "instruction" => "Rename the page." }, call["input"])
    assert_equal({ "error" => "The title was not saved." }, call["output"])
  end

  test "a turn that is still going says so" do
    entries = PlaygroundSteps.build(
      [ Turn.new(status: "running", text: nil, error_message: nil, asked: [], heard: []) ],
      instruction: "Find the staff handbook.",
      status: "running"
    )

    assert_equal "On it", entries.first.title
    assert_equal "Working", entries.first.badge
    call = JSON.parse(entries.first.exchange)
    assert_equal({ "instruction" => "Find the staff handbook." }, call["input"])
    assert_nil call["output"]
  end

  test "a failed turn prefers that turn's error" do
    entries = PlaygroundSteps.build(
      [ Turn.new(status: "failed", text: " ", error_message: "The model stopped.", asked: [], heard: []) ],
      failure_message: "The title was not saved.",
      instruction: "Rename the page.",
      status: "failed"
    )

    assert_equal "Did not finish", entries.first.title
    assert_equal "Failed", entries.first.badge
    call = JSON.parse(entries.first.exchange)
    assert_equal({ "error" => "The model stopped." }, call["output"])
  end

  test "agent steps show the plan, the tool, and the answer" do
    workspace = Workspace.create!(name: "Playground Steps #{SecureRandom.hex(4)}")
    root = RecordingStudio.root_recording_for(workspace)
    user = User.create!(
      email: "playground-steps-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    task = RecordingStudioAgents::Task.create!(
      root_recording_id: root.id,
      task_key: "playground-steps:#{SecureRandom.hex(4)}",
      goal: "Find the staff handbook.",
      input_digest: "playground-steps"
    )
    run = RecordingStudioAgents::AgentRun.create!(
      task: task,
      root_recording_id: root.id,
      agent_key: "page_librarian",
      agent_version: 1,
      program_digest: "playground-steps",
      idempotency_key: "playground-steps:#{SecureRandom.uuid}",
      status: "succeeded",
      initiator_type: "User",
      initiator_id: user.id.to_s,
      initiator_kind: "user",
      execution_source: "web",
      working_state_json: { "current_objective" => "Find the named page", "goal" => "Find the staff handbook." }
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 1, status: "completed", action_type: "reason",
      observation_summary: "Find the named page"
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 2, status: "completed", action_type: "tool",
      tool_key: "find_page", tool_version: 1, observation_summary: "Found the page.", progress_made: true
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 3, status: "completed", action_type: "deliver",
      observation_summary: "Found the Staff handbook."
    )

    entries = PlaygroundSteps.for(run, initiator: user)

    assert_equal [ "Plan", "Find page", "Answer" ], entries.map(&:title)
    answer = JSON.parse(entries.last.exchange)
    assert_equal "deliver", answer["action"]
    assert_equal "Find the named page", answer["now"]
    assert_equal "Found the Staff handbook.", answer["observation"]
    refute_includes entries.last.exchange, "arguments"
  end

  test "the collapse renders the call as one hash" do
    step = PlaygroundSteps::Entry.new(
      id: "playground-step-1",
      title: "Find page",
      badge: "Done",
      badge_style: :success,
      exchange: JSON.pretty_generate(
        "input" => { "instruction" => "Find the staff handbook." },
        "output" => { "find_page" => { "title" => "Staff handbook" } }
      )
    )

    html = ApplicationController.render(partial: "playground/results", assigns: { steps: [ step ] })

    assert_includes html, "input"
    assert_includes html, "output"
    assert_includes html, "Find the staff handbook."
    assert_includes html, "Staff handbook"
    refute_includes html, "Given"
    refute_includes html, "Returned"
    assert_includes html, "playground-step-1-content"
  end
end
