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
    assert_includes response.body, "Attempts this period"
    assert_includes response.body, "Tokens this period"
    assert_includes response.body, "Hungry agents"
    assert_select "a", text: "Runs"
    assert_select "a", text: "Tasks"
    assert_select "a", text: "Usage by agent"
    assert_select "a", text: "Agent list"
    assert_includes response.body, "/admin/screens/agent_runs"
    assert_includes response.body, "/admin/screens/agent_tasks"
    assert_includes response.body, "/admin/screens/agent_usage"
    assert_includes response.body, "/admin/screens/registered_agents"
    refute_includes response.body, "/admin/screens/registered_skills"
    refute_includes response.body, "/admin/screens/registered_skill_packs"
    refute_includes response.body, "Skill packs"
    refute_includes response.body, "By agent"
    assert_includes response.body, "12k tokens"
    assert_includes response.body, "Last 4 weeks"
    refute_includes response.body, "Last 30 days"
    refute_includes response.body, "widgets.agents.run_count"

    get "/admin/screens/registered_agents"
    assert_response :success
    assert_includes response.body, "Agent list"
    assert_includes response.body, 'id="screen-table"'
    assert_includes response.body, "/admin/screens/registered_agents/table"

    get "/admin/screens/registered_agents/table"
    assert_response :success
    assert_includes response.body, "page_librarian"
    assert_includes response.body, "page_reviewer"
    assert_includes response.body, "support_clerk"

    get "/admin/screens/agent_tasks"
    assert_response :success
    assert_includes response.body, "Tasks"
    refute_includes response.body, "seed:find_page"

    get "/admin/screens/agent_tasks/table"
    assert_response :success
    assert_includes response.body, "Find the Getting Started page."
    refute_includes response.body, "seed:find_page"

    get "/admin/screens/agent_runs"
    assert_response :success
    assert_includes response.body, "Runs"
    assert_includes response.body, 'id="screen-table"'
    assert_includes response.body, "/admin/screens/agent_runs/table"
    assert_includes response.body, 'value="Last 4 weeks"'
    refute_match(/value="\d{4}-\d{2}-\d{2} to \d{4}-\d{2}-\d{2}"/, response.body)

    get "/admin/screens/agent_runs/table"
    assert_response :success
    assert_includes response.body, "page_librarian"
    assert_includes response.body, "failed"
    assert_includes response.body, "Steps"
    assert_includes response.body, "Tokens"
    assert_includes response.body, "Tools"
    assert_includes response.body, "Did not finish"
    assert_includes response.body, "12,000"
    assert_match(/tool_calls\?.*run_id=/, response.body)
    assert_match(/ai_calls\?.*search=/, response.body)

    get "/admin/screens/agent_usage"
    assert_response :success
    assert_includes response.body, "Usage by agent"
    assert_includes response.body, "Attempts, outcomes, and average tokens."
    refute_includes response.body, "By agent"
    assert_includes response.body, 'id="screen-table"'
    assert_includes response.body, "/admin/screens/agent_usage/table"
    assert_includes response.body, 'value="Last 4 weeks"'
    refute_match(/value="\d{4}-\d{2}-\d{2} to \d{4}-\d{2}-\d{2}"/, response.body)

    get "/admin/screens/agent_usage/table"
    assert_response :success
    assert_includes response.body, "page_librarian"
    assert_includes response.body, "Avg tokens"
    assert_includes response.body, "12,000"
  end
end
