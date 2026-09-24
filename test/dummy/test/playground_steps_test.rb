# frozen_string_literal: true

require "test_helper"

class PlaygroundStepsTest < ActiveSupport::TestCase
  Turn = PlaygroundSteps::Turn
  ToolNote = PlaygroundSteps::ToolNote

  test "each turn shows its own input and response" do
    asked = ToolNote.new(name: "Find page", body: "{\n  \"title\": \"Staff handbook\"\n}")
    heard = ToolNote.new(name: "Find page", body: "{\n  \"found\": true\n}")
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
    assert_equal "Find the staff handbook.\n\n{\"folder\":\"People\"}", entries.first.given
    assert_includes entries.first.returned, "\"title\": \"Staff handbook\""
    refute_includes entries.first.returned, "Found the Staff handbook."

    assert_equal "Reply", entries.second.title
    assert_includes entries.second.given, "\"found\": true"
    refute_includes entries.second.given, "Find the staff handbook."
    assert_equal "Found the Staff handbook.", entries.second.returned
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
    assert_equal "Find the staff handbook.", entries.first.given
    assert_equal "Still going.", entries.first.returned
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
    assert_equal "Rename the page.", entries.first.given
    assert_equal "The title was not saved.", entries.first.returned
  end

  test "a turn that is still going says so" do
    entries = PlaygroundSteps.build(
      [ Turn.new(status: "running", text: nil, error_message: nil, asked: [], heard: []) ],
      instruction: "Find the staff handbook.",
      status: "running"
    )

    assert_equal "On it", entries.first.title
    assert_equal "Working", entries.first.badge
    assert_equal "Find the staff handbook.", entries.first.given
    assert_equal "Still going.", entries.first.returned
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
    assert_equal "The model stopped.", entries.first.returned
  end

  test "the collapse renders given and returned" do
    step = PlaygroundSteps::Entry.new(
      id: "playground-step-1",
      title: "Find page",
      badge: "Done",
      badge_style: :success,
      given: "Find the staff handbook.",
      returned: "Find page\n{\"title\":\"Staff handbook\"}"
    )

    html = ApplicationController.render(partial: "playground/results", assigns: { steps: [ step ] })

    assert_includes html, "Given"
    assert_includes html, "Find the staff handbook."
    assert_includes html, "Returned"
    assert_includes html, "Staff handbook"
    assert_includes html, "playground-step-1-content"
  end
end
