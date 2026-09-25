# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class WebResearchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "web search is mounted and the researcher is registered" do
    get "/addons/recording"

    assert_response :success
    assert_equal :brave, RecordingStudio::WebSearch.configuration.provider
    assert_nil RecordingStudio::WebSearch.configuration.brave_api_key
    assert_includes Rails.root.join("config/initializers/recording_studio_web_search.rb").read, "brave_search"

    tool = RecordingStudioAI.tools.fetch(:web_search, version: 1)
    assert_equal "Web search", tool.name

    skill = RecordingStudioAgents.skills.fetch(:web_research, version: 1)
    assert_equal "Web research", skill.name
    assert_equal [ "web_search" ], skill.required_tools.map(&:key)
    assert_includes skill.instructions, "Lead with the answer"
    assert_includes skill.instructions, "Cite only pages that came back"

    agent = RecordingStudioAgents.agents.fetch(:web_researcher, version: 1)
    assert_equal "Web researcher", agent.name
    assert_equal [ "web_research" ], agent.skills.map(&:key)
    assert_equal [ "web_search" ], agent.tools.map(&:key)
    assert agent.enabled
  end

  test "brave_search is read only when the suite is allowed online" do
    previous = ENV["brave_search"]
    ENV["brave_search"] = "brave-secret"

    assert_nil DummyAIProviderKeys.read("brave_search", offline: true)
    assert_equal "brave-secret", DummyAIProviderKeys.read("brave_search", offline: false)
  ensure
    previous.nil? ? ENV.delete("brave_search") : ENV["brave_search"] = previous
  end

  test "staff can open the web search section" do
    user = User.find_or_create_by!(email: "web-search-admin@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    admin_root = AdminRoot.find_or_create_by!(name: "Admin")
    grant_accessible!(recording: RecordingStudio.root_recording_for(admin_root), actor: user)
    sign_in user

    get "/admin/sections/web_search"

    assert_response :success
    assert_includes response.body, "Web search"
    assert_includes response.body, "Providers"
    assert_includes response.body, "Searches"
  end
end
