# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AgentsDemoTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "librarian-demo@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    @workspace = Workspace.find_or_create_by!(name: "Librarian Demo")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_accessible!(recording: @root, actor: @user)
    sign_in @user
    switch_to_root!(@root)
  end

  test "home mounts the page librarian demo" do
    get "/"

    assert_response :success
    assert_includes response.body, "Page librarian"
    assert_includes response.body, "Find Getting Started"
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
  end

  test "demo run creates a task and a succeeded run without a live provider" do
    assert_difference -> { RecordingStudioAgents::AgentRun.count }, 1 do
      post "/agents/demo"
    end

    assert_redirected_to "/"
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Found it."
    assert_includes response.body, "What it did"
    assert_includes response.body, "Checked this workspace"
    assert_includes response.body, "Find page"
    assert_includes response.body, "Done"
    refute_includes response.body, "find_page"
    refute_includes response.body, "Retitle page"
    refute_includes response.body, "lookup_invoice"

    run = RecordingStudioAgents::AgentRun.order(:created_at).last
    assert_equal "page_librarian", run.agent_key
    assert_equal "succeeded", run.status
    assert run.output_digest.present?
    refute_includes run.attributes.keys, "output_text"
    assert RecordingStudioAI::CustomToolInvocation.exists?(
      run_id: run.recording_studio_ai_run_id,
      tool_key: "find_page",
      tool_name_snapshot: "Find page"
    )

    run.update_column(:recording_studio_ai_run_id, nil)
    labels = RecordingStudioAgents::Progress.for(run.reload).map(&:label)
    assert_includes labels, "Find page"
    assert_includes labels, "Checked this workspace"
    assert_includes labels, "Done"
  end
end
