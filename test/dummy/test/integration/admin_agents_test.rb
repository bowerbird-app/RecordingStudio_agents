# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminAgentsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "admin requires a signed-in user" do
    get "/admin"

    assert_includes [ 401, 302 ], response.status
  end

  test "signed-in user without admin root access is forbidden" do
    user = User.find_or_create_by!(email: "admin-no-access@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    admin_root = AdminRoot.find_or_create_by!(name: "Admin")
    RecordingStudio.root_recording_for(admin_root)
    sign_in user

    get "/admin"

    assert_response :forbidden
  end

  test "admin lists the seeded failed run" do
    user = User.find_or_create_by!(email: "admin-agents@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    admin_root = AdminRoot.find_or_create_by!(name: "Admin")
    admin_root_recording = RecordingStudio.root_recording_for(admin_root)

    workspace = Workspace.find_or_create_by!(name: "Admin Inspect Workspace")
    workspace_root = RecordingStudio.root_recording_for(workspace)

    load Rails.root.join("db/seeds.rb").to_s
    studio = Workspace.find_by!(name: "Studio Workspace")
    grant_accessible!(recording: admin_root_recording, actor: user)
    grant_accessible!(recording: workspace_root, actor: user)
    grant_accessible!(recording: RecordingStudio.root_recording_for(studio), actor: user)
    sign_in user

    get "/admin"
    assert_response :success
    assert_includes response.body, "Agents"

    get "/admin/screens/registered_agents"
    assert_response :success
    assert_includes response.body, 'id="screen-table"'
    assert_includes response.body, "/admin/screens/registered_agents/table"

    get "/admin/screens/registered_agents/table"
    assert_response :success
    assert_includes response.body, "page_librarian"
    assert_includes response.body, "page_reviewer"
    assert_includes response.body, "support_clerk"

    get "/admin/screens/registered_skills/table"
    assert_response :success
    assert_includes response.body, "page_lookup"
    assert_includes response.body, "billing_help"

    get "/admin/screens/registered_skill_packs/table"
    assert_response :success
    assert_includes response.body, "billing_tickets"

    get "/admin/screens/agent_tasks/table"
    assert_response :success
    assert_includes response.body, "Find the Getting Started page."

    get "/admin/screens/agent_runs"
    assert_response :success
    assert_includes response.body, "Runs"
    assert_includes response.body, 'id="screen-table"'
    assert_includes response.body, "/admin/screens/agent_runs/table"

    get "/admin/screens/agent_runs/table"
    assert_response :success
    assert_includes response.body, "page_librarian"
    assert_includes response.body, "failed"
    assert_includes response.body, "Extra skills"
  end
end
