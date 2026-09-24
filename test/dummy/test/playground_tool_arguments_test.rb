# frozen_string_literal: true

require "test_helper"

class PlaygroundToolArgumentsTest < ActiveSupport::TestCase
  test "a tool invocation keeps the arguments that were passed in" do
    workspace = Workspace.create!(name: "Tool Arguments #{SecureRandom.hex(4)}")
    root = RecordingStudio.root_recording_for(workspace)
    user = User.create!(
      email: "tool-arguments-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
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
      request_id: "playground-arguments-#{SecureRandom.hex(4)}",
      started_at: now
    )
    tool_call = RecordingStudioAI::Providers::ToolCall.new(
      provider_tool_call_id: "call-#{SecureRandom.hex(4)}",
      key: "find_page",
      arguments: { "title" => "Staff handbook" }
    )
    definition = RecordingStudioAI.tools.fetch(:find_page, version: 1)

    invocation = RecordingStudioAI::Orchestration::CustomToolRecords.new.create!(
      ai_run,
      nil,
      tool_call,
      definition
    )

    assert_equal({ "title" => "Staff handbook" }, invocation.reload.metadata["arguments"])
  end
end
