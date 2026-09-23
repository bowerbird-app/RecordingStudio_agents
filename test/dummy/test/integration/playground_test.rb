# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class PlaygroundTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @user = User.find_or_create_by!(email: "playground@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    @workspace = Workspace.find_or_create_by!(name: "Playground")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_accessible!(recording: @root, actor: @user)
    sign_in @user
    switch_to_root!(@root)
  end

  test "playground lists registered agents and a sidebar link" do
    get "/playground"

    assert_response :success
    assert RecordingStudioAI.configuration.retain_responses
    assert_includes response.body, "Playground"
    assert_includes response.body, "Try an agent on this workspace and watch the steps."
    assert_select "textarea[name='goal']"
    assert_includes response.body, "Page librarian"
    assert_includes response.body, "Support clerk"
    assert_select "a[href='/playground']", text: /Playground/
  end

  test "page librarian run shows steps and the reply" do
    assert_enqueued_jobs 1, only: PlaygroundRunJob do
      post "/playground", params: {
        agent: "page_librarian@1",
        goal: "Find the Getting Started page."
      }
    end

    assert_response :redirect
    path = redirected_playground_path
    assert_match %r{\A/playground/runs/playground:[0-9a-f-]{36}\z}, path

    get path
    assert_response :success
    assert_includes response.body, "Starting."
    assert_includes response.body, "http-equiv=\"refresh\""

    perform_enqueued_jobs
    get path
    assert_response :success
    assert_includes response.body, "Find the Getting Started page."
    assert_includes response.body, "Page librarian"
    assert_includes response.body, "Find page"
    assert_includes response.body, "Open the model call"
    assert_includes response.body, "Done"
    assert_includes response.body, "Finished."
    assert_not_includes response.body, "http-equiv=\"refresh\""
    assert_not_includes response.body, "find_page"

    run = RecordingStudioAgents::AgentRun.find_by!(
      root_recording_id: @root.id,
      idempotency_key: path.split("/").last
    )
    assert_equal "page_librarian", run.agent_key
    assert_equal "succeeded", run.status
  end

  test "support clerk keeps the selected extra skill and pack" do
    assert_enqueued_jobs 1, only: PlaygroundRunJob do
      post "/playground", params: {
        agent: "support_clerk@1",
        goal: "Help with this refund.",
        extra_skills: [ "billing_help@1" ],
        pack: "billing_tickets@1"
      }
    end

    assert_response :redirect
    perform_enqueued_jobs

    run = RecordingStudioAgents::AgentRun.find_by!(
      root_recording_id: @root.id,
      idempotency_key: redirected_playground_path.split("/").last
    )
    assert_includes run.selected_skills_json, { "key" => "billing_help", "version" => 1 }
    assert_equal "billing_tickets", run.skill_pack_key
  end

  test "invalid context redisplays the form and does not enqueue" do
    assert_no_enqueued_jobs do
      post "/playground", params: {
        agent: "page_librarian@1",
        goal: "Find the Getting Started page.",
        context: "{not json"
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "That is not JSON."
    assert_select "textarea[name='goal']"
  end

  test "an extra skill the agent did not allow redisplays and does not enqueue" do
    assert_no_enqueued_jobs do
      post "/playground", params: {
        agent: "page_librarian@1",
        goal: "Find the Getting Started page.",
        extra_skills: [ "billing_help@1" ]
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "That extra help is not on this agent."
    assert_select "textarea[name='goal']"
  end

  test "signed out playground is not public" do
    sign_out @user

    get "/playground"

    assert_includes [ 302, 401 ], response.status
  end

  private

  def redirected_playground_path
    location = URI.parse(response.location)
    URI.decode_www_form_component(location.path)
  end
end
