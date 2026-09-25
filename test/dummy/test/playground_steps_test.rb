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
      working_state_json: {
        "current_objective" => "Report the later objective",
        "plan" => [ "This plan was written later" ],
        "goal" => "Find the staff handbook."
      }
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 1, status: "completed", action_type: "reason",
      observation_summary: "Find the named page",
      record_json: {
        "objective" => "Find the named page",
        "plan" => [ "Look up the handbook", "Answer" ],
        "criteria" => [ "The handbook title is quoted" ]
      }
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 2, status: "completed", action_type: "decide",
      controller_outcome: { "name" => "tool", "reason" => "selected", "finished" => 0.07, "stuck" => 0.16 }
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 3, status: "completed", action_type: "tool",
      tool_key: "find_page", tool_version: 1, observation_summary: "Found the page.", progress_made: true
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 4, status: "completed", action_type: "arguments",
      tool_key: "find_page", tool_version: 1, observation_summary: "Filled the required arguments."
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 5, status: "completed", action_type: "reason",
      observation_summary: "Asked for the next actions.",
      record_json: { "actions" => [ "find_page v1. Look up the next page" ] }
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 6, status: "completed", action_type: "deliver",
      observation_summary: "Found the Staff handbook."
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 7, status: "completed", action_type: "handoff",
      record_json: { "reviewer" => "page_reviewer v1" }
    )

    entries = PlaygroundSteps.for(run, initiator: user)

    assert_equal(
      [ "Plan", "Checked in", "Find page", "Filled in", "Next actions", "Answer", "Asked for a reviewer" ],
      entries.map(&:title)
    )
    assert_equal <<~TEXT.chomp, entries.first.exchange
      Find the named page

      Plan
      Look up the handbook
      Answer

      Done when
      The handbook title is quoted
    TEXT
    refute_includes entries.first.exchange, "Report the later objective"
    refute_includes entries.first.exchange, "This plan was written later"
    assert_equal "Picked a tool.\nFinished 0.07. Stuck 0.16.", entries.second.exchange
    refute_includes entries.second.exchange, "Report the later objective"
    assert_equal "Found the page.", entries[2].exchange
    assert_equal "Find page. Filled the required arguments.", entries[3].exchange
    assert_equal "Asked for the next actions.\n\nfind_page v1. Look up the next page", entries[4].exchange
    assert_equal "Found the Staff handbook.", entries[5].exchange
    assert_equal "Asked page_reviewer v1.", entries[6].exchange
    refute_includes entries.map(&:exchange).join, "{"
  end

  test "an older plan step shows the note written then" do
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
      goal: "Pages about cats",
      input_digest: "playground-steps"
    )
    run = RecordingStudioAgents::AgentRun.create!(
      task: task,
      root_recording_id: root.id,
      agent_key: "page_librarian",
      agent_version: 1,
      program_digest: "playground-steps",
      idempotency_key: "playground-steps:#{SecureRandom.uuid}",
      status: "handoff_requested",
      initiator_type: "User",
      initiator_id: user.id.to_s,
      initiator_kind: "user",
      execution_source: "web",
      handoff_agent_key: "page_reviewer",
      handoff_agent_version: 1,
      working_state_json: {
        "current_objective" => "Report that no pages about cats were found and request a handoff.",
        "plan" => [ "This plan was written later" ]
      }
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 1, status: "completed", action_type: "reason",
      observation_summary: "Find pages about cats."
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 2, status: "completed", action_type: "handoff"
    )

    entries = PlaygroundSteps.for(run, initiator: user)

    assert_equal [ "Plan", "Asked for a reviewer" ], entries.map(&:title)
    assert_equal "Find pages about cats.", entries.first.exchange
    refute_includes entries.first.exchange, "Report that no pages about cats were found"
    assert_equal "Asked page_reviewer v1.", entries.second.exchange
  end

  test "a failed run shows why it stopped" do
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
      goal: "Pages about cats",
      input_digest: "playground-steps"
    )
    run = RecordingStudioAgents::AgentRun.create!(
      task: task,
      root_recording_id: root.id,
      agent_key: "page_librarian",
      agent_version: 1,
      program_digest: "playground-steps",
      idempotency_key: "playground-steps:#{SecureRandom.uuid}",
      status: "failed",
      failure_code: "maximum_replans",
      failure_message: "Agent run stopped at maximum_replans.",
      initiator_type: "User",
      initiator_id: user.id.to_s,
      initiator_kind: "user",
      execution_source: "web"
    )
    RecordingStudioAgents::AgentStep.create!(
      agent_run: run, sequence: 1, status: "completed", action_type: "decide",
      controller_outcome: { "name" => "reason", "reason" => "uncertain", "finished" => 0.36, "stuck" => 0.73 }
    )

    entries = PlaygroundSteps.for(run, initiator: user)

    assert_equal [ "Checked in", "Did not finish" ], entries.map(&:title)
    assert_equal "Asked for a new plan.\nFinished 0.36. Stuck 0.73.", entries.first.exchange
    assert_equal [ "Failed", :danger ], [ entries.last.badge, entries.last.badge_style ]
    assert_equal "Agent run stopped at maximum_replans.", entries.last.exchange
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
