# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class ConfigurableLayoutTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @agents = RecordingStudioAgents.configuration
    @studio = RecordingStudio.configuration
    @previous_agents_layout = @agents.layout
    @previous_studio_layout = @studio.layout
    @user = User.find_or_create_by!(email: "layout-test@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
  end

  teardown do
    @agents.layout = @previous_agents_layout
    @studio.layout = @previous_studio_layout
  end

  test "nil layout uses the host layout and then the default template" do
    @agents.layout = nil
    @studio.layout = "application"
    sign_in @user

    get root_path

    assert_response :success
    refute_includes response.body, "data-recording-studio-default-layout"
    assert_includes response.body, "Rails engine routes are mounted"

    @studio.layout = nil

    get root_path

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "h1", text: "Template Demo", count: 1
    assert_select "header nav[aria-label='Page navigation']", count: 1
  end

  test "a string layout name is used as given" do
    @agents.layout = "application"
    @studio.layout = nil
    sign_in @user

    get root_path

    assert_response :success
    refute_includes response.body, "data-recording-studio-default-layout"
    assert_includes response.body, "min-h-screen"
  end

  test "false renders the page with no layout" do
    @agents.layout = false
    @studio.layout = "recording_studio/default_layout"
    sign_in @user

    get root_path

    assert_response :success
    refute_includes response.body, "data-recording-studio-default-layout"
    refute_includes response.body, "<html"
    assert_includes response.body, "Rails engine routes are mounted"
  end

  test "a keyword layout callable receives the controller" do
    @agents.layout = ->(controller:) { controller.controller_name == "home" ? "application" : nil }
    @studio.layout = nil
    sign_in @user

    get root_path

    assert_response :success
    refute_includes response.body, "data-recording-studio-default-layout"

    get agent_chat_path

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "h1", text: "Agent chat", count: 1
  end

  test "devise keeps the auth layout and chatkit stays json" do
    @agents.layout = nil
    @studio.layout = nil

    get new_user_session_path

    assert_response :success
    refute_includes response.body, "data-recording-studio-default-layout"

    post "/recording_studio_agents/chatkit", params: { type: "threads.list", params: {} }, as: :json

    assert_response :unauthorized
    assert_equal "application/json", response.media_type
    refute_includes response.body, "data-recording-studio-default-layout"
  end

  test "press kits render one heading inside the default layout" do
    @agents.layout = nil
    @studio.layout = nil
    sign_in @user

    get press_kits_path

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "h1", text: "Press kits", count: 1
    assert_select "header nav[aria-label='Page navigation']", count: 1
  end

  test "controllers do not hard-code a recording studio layout" do
    assert_empty RecordingStudio::Layout.hardcoded_layout_paths(Rails.root)
    assert_empty RecordingStudio::Layout.hardcoded_layout_paths(RecordingStudioAgents::Engine.root)
  end
end
