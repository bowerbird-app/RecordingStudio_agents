# frozen_string_literal: true

require "test_helper"

class ContextRecordingRootTest < ActiveSupport::TestCase
  include AccessibleTestHelpers

  setup do
    @user = User.find_or_create_by!(email: "context-root@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    @home = Workspace.create!(name: "Context Home #{SecureRandom.hex(4)}")
    @other = Workspace.create!(name: "Context Other #{SecureRandom.hex(4)}")
    @home_root = RecordingStudio.root_recording_for(@home)
    @other_root = RecordingStudio.root_recording_for(@other)
    grant_accessible!(recording: @home_root, actor: @user)
    grant_accessible!(recording: @other_root, actor: @user)
  end

  test "accepts a page inside the task workspace as context" do
    page_recording = record_page(@home_root, "Home Getting Started")
    result = stub_generate do
      RecordingStudioAgents.agent(:page_librarian, version: 1).run(
        task: task_input,
        root_recording: @home_root,
        context_recording: page_recording,
        initiator: @user,
        execution_source: :job,
        idempotency_key: "dummy-context-home"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_equal page_recording.id, result.run.context_recording_id
  end

  test "rejects a page from another workspace as context" do
    outsider = record_page(@other_root, "Other Getting Started")
    generate_called = false

    error = assert_raises(RecordingStudioAgents::ContractError) do
      stub_generate(on_call: -> { generate_called = true }) do
        RecordingStudioAgents.agent(:page_librarian, version: 1).run(
          task: task_input,
          root_recording: @home_root,
          context_recording: outsider,
          initiator: @user,
          execution_source: :job,
          idempotency_key: "dummy-context-outsider"
        )
      end
    end

    refute generate_called
    assert_match(/task root/, error.message)
    assert_equal 0, RecordingStudioAgents::AgentRun.where(root_recording_id: @home_root.id).count
  end

  private

  def record_page(root_recording, title)
    RecordingStudio.record!(
      action: "created",
      recordable: Page.new(title: title),
      root_recording: root_recording,
      parent_recording: root_recording
    ).recording
  end

  def stub_generate(on_call: nil)
    response = RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_page_librarian",
      text: "Found it."
    )
    DummyGenerateStub.with_hook(lambda { |**|
      on_call&.call
      response
    }) do
      yield
    end
  end

  def task_input
    RecordingStudioAgents::TaskInput.new(
      key: "find_page:#{@home_root.id}:#{SecureRandom.uuid}",
      goal: "Find the Getting Started page.",
      context: {}
    )
  end
end
