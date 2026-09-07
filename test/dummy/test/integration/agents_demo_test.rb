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

    run = RecordingStudioAgents::AgentRun.order(:created_at).last
    assert_equal "page_librarian", run.agent_key
    assert_equal "succeeded", run.status
    assert run.output_digest.present?
    refute_includes run.attributes.keys, "output_text"
  end
end
