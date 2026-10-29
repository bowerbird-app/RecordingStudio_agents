# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class ChatkitPopupTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "popup-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @configuration = RecordingStudioAgents.configuration
    @previous_domain_key = @configuration.chatkit_domain_key
    @previous_origins = @configuration.chatkit_allowed_origins
    @previous_sign_in_path = @configuration.sign_in_path
    @previous_actor = @configuration.request_actor
    @previous_root = @configuration.request_root
    @ai = RecordingStudioAI.configuration
    @previous_handler = @ai.authorization_handler
    @previous_api_key = @ai.openai_api_key
    @configuration.chatkit_domain_key = nil
    @ai.openai_api_key = nil
  end

  teardown do
    @configuration.chatkit_domain_key = @previous_domain_key
    @configuration.chatkit_allowed_origins = @previous_origins
    @configuration.sign_in_path = @previous_sign_in_path
    @configuration.request_actor = @previous_actor
    @configuration.request_root = @previous_root
    @ai.authorization_handler = @previous_handler
    @ai.openai_api_key = @previous_api_key
  end

  test "a signed in popup renders the chat setup and a popup content security policy" do
    sign_in @user

    get recording_studio_agents.popup_path

    assert_response :success
    assert_includes response.body, "ChatKit setup"
    assert_includes response.body, 'data-theme="rounded"'
    refute_includes response.body, "data-recording-studio-default-layout"
    refute_includes response.body, "page_recording_id"
    refute_includes response.body, "Sign in to chat"
    assert_popup_policy
    assert_nil response.headers["X-Frame-Options"]
  end

  test "a signed out popup shows the sign in state and no chat" do
    get recording_studio_agents.popup_path

    assert_response :success
    assert_includes response.body, "Sign in to chat"
    assert_includes response.body, "Your chats stay on your account."
    assert_select "a[href='/users/sign_in']", text: "Sign in"
    assert_select "openai-chatkit", count: 0
    refute_includes response.body, "ChatKit setup"
    refute_includes response.body, "cdn.platform.openai.com/deployments/chatkit/chatkit.js"
    refute_includes response.body, "data-recording-studio-default-layout"
    assert_popup_policy
  end

  test "french popup copy is available" do
    I18n.with_locale(:fr) do
      get recording_studio_agents.popup_path
    end

    assert_response :success
    assert_includes response.body, "Connectez-vous pour discuter"
    assert_includes response.body, "Se connecter"
    assert_includes response.body, "<title>Discussion</title>"
  end

  test "a signed out chat request is refused" do
    post "/recording_studio_agents/chatkit",
         params: { type: "threads.create", params: { input: { content: [{ type: "input_text", text: "hello" }] } } },
         as: :json

    assert_response :unauthorized
    assert_equal "sign in is required", JSON.parse(response.body).fetch("message")
    assert_nil response.headers["Content-Security-Policy"]
  end

  test "a denied execute returns forbidden instead of an error page" do
    root = RecordingStudio.root_recording_for(Workspace.create!(name: "Popup #{SecureRandom.hex(4)}"))
    grant_edit(@user, root)
    @configuration.request_actor = ->(*) { @user }
    @configuration.request_root = ->(*) { root }
    @ai.authorization_handler = ->(**) { false }

    post "/recording_studio_agents/chatkit",
         params: { type: "threads.create", params: { input: { content: [{ type: "input_text", text: "hello" }] } } },
         as: :json

    assert_response :forbidden
    assert_includes JSON.parse(response.body).fetch("message"), "recording_studio_ai.execute"
  end

  test "a workspace chat keeps the application content security policy" do
    sign_in @user

    get agent_chat_path

    assert_response :success
    assert_nil response.headers["Content-Security-Policy"]
    assert_includes response.body, "data-recording-studio-default-layout"
  end

  test "a callable sign in path is used on the button" do
    @configuration.sign_in_path = ->(controller) { "#{controller.main_app.new_user_session_path}?from=popup" }

    get recording_studio_agents.popup_path

    assert_response :success
    assert_select "a[href='/users/sign_in?from=popup']", text: "Sign in"
  end

  test "a configured popup fills the iframe and stays on the workspace chat" do
    sign_in @user
    @configuration.chatkit_domain_key = "domain_pk_test"
    @ai.openai_api_key = "sk-test"

    get recording_studio_agents.popup_path

    assert_response :success
    assert_select "openai-chatkit", count: 1
    assert_includes response.body, "h-dvh"
    refute_includes response.body, "h-[min(40rem,calc(100dvh-16rem))]"
    assert_includes response.body, "/recording_studio_agents/chatkit"
    refute_includes response.body, "page_recording_id"
    refute_includes response.body, "sk-test"
  end

  test "configured origins are added to frame ancestors" do
    sign_in @user
    @configuration.chatkit_allowed_origins = ["https://staging.example"]

    get recording_studio_agents.popup_path

    assert_response :success
    policy = response.headers["Content-Security-Policy"]
    assert_includes policy, "https://staging.example"
    refute_includes policy, "http://localhost:3000"
  end

  private

  def assert_popup_policy
    policy = response.headers["Content-Security-Policy"]
    assert policy
    assert_includes policy, "script-src"
    assert_includes policy, "connect-src"
    assert_includes policy, "frame-src"
    assert_includes policy, "frame-ancestors"
    assert_includes policy, "https://cdn.platform.openai.com"
    assert_includes policy, "https://api.openai.com"
    assert_includes policy, "'self'"
    assert_includes policy, "http://localhost:3000"
    assert_includes policy, "http://127.0.0.1:3000"
    policy
  end

  def grant_edit(actor, recording)
    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(recording).record(
        RecordingStudio::Access, actor: actor, parent_recording: recording
      ) do |access|
        access.actor = actor
        access.role = "edit"
      end
    end
  end
end
