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
    @previous_stylesheet = @configuration.popup_stylesheet
    @previous_theme = @configuration.popup_theme
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
    @configuration.popup_stylesheet = @previous_stylesheet
    @configuration.popup_theme = @previous_theme
    @configuration.request_actor = @previous_actor
    @configuration.request_root = @previous_root
    @ai.authorization_handler = @previous_handler
    @ai.openai_api_key = @previous_api_key
  end

  test "a signed in popup renders the chat setup and a popup content security policy" do
    sign_in_with_workspace

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

  test "a signed in person with no workspace sees an empty state instead of the chat" do
    sign_in @user
    @configuration.request_root = ->(*) { nil }

    get recording_studio_agents.popup_path

    assert_response :success
    assert_includes response.body, "Pick a workspace"
    assert_includes response.body, "Open one, then come back to chat."
    assert_select "openai-chatkit", count: 0
    refute_includes response.body, "Sign in to chat"
    refute_includes response.body, "flex h-dvh"
  end

  test "the popup theme attribute comes from config and defaults to rounded" do
    sign_in_with_workspace

    get recording_studio_agents.popup_path

    assert_response :success
    assert_select "html[data-theme=?]", "rounded"

    @configuration.popup_theme = "featured-in"
    get recording_studio_agents.popup_path

    assert_response :success
    assert_select "html[data-theme=?]", "featured-in"
  end

  test "a custom popup stylesheet renders its link and nil renders none" do
    sign_in_with_workspace
    @configuration.popup_stylesheet = "popup-sheet"

    get recording_studio_agents.popup_path

    assert_response :success
    assert_select "link[rel=stylesheet][href*='popup-sheet']", count: 1

    @configuration.popup_stylesheet = nil
    get recording_studio_agents.popup_path

    assert_response :success
    assert_select "link[rel=stylesheet][href*='popup-sheet']", count: 0
    assert_select "link[rel=stylesheet][href*='tailwind']", count: 0
    assert_select "link[rel=stylesheet][href*='flat_pack/variables']", count: 1
    assert_select "link[rel=stylesheet][href*='flat_pack/application']", count: 1
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
    sign_in_with_workspace
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

  test "the popup setup script is an asset and does not need a nonce" do
    assert_nil Rails.application.config.content_security_policy_nonce_generator
    sign_in_with_workspace
    @configuration.chatkit_domain_key = "domain_pk_test"
    @ai.openai_api_key = "sk-test"

    get recording_studio_agents.popup_path

    assert_response :success
    assert_select "script:not([src])", count: 0
    assert_select "script[src*='recording_studio_agents/chatkit']", count: 1
    assert_select "script[src*='cdn.platform.openai.com']", count: 1
    script_src = response.headers["Content-Security-Policy"][/script-src[^;]*/]
    assert_includes script_src, "'self'"
    assert_includes script_src, "https://cdn.platform.openai.com"
    refute_includes script_src, "unsafe-inline"
    refute_includes script_src, "nonce-"
  end

  test "a configured asset host is allowed and used for the setup script" do
    sign_in_with_workspace
    @configuration.chatkit_domain_key = "domain_pk_test"
    @ai.openai_api_key = "sk-test"

    with_asset_host("https://cdn.example.test/static") do
      get recording_studio_agents.popup_path
    end

    assert_response :success
    script_src = response.headers["Content-Security-Policy"][/script-src[^;]*/]
    assert_includes script_src, "https://cdn.example.test"
    refute_includes script_src, "/static"
    assert_select "script[src^='https://cdn.example.test/'][src*='recording_studio_agents/chatkit']", count: 1
  end

  test "a two argument asset host proc is allowed and used for the setup script" do
    sign_in_with_workspace
    @configuration.chatkit_domain_key = "domain_pk_test"
    @ai.openai_api_key = "sk-test"
    host = proc { |_source, request| request.ssl? ? "https://secure.example.test" : "http://plain.example.test" }

    with_asset_host(host) do
      get recording_studio_agents.popup_path
    end

    assert_response :success
    src = css_select("script[src*='recording_studio_agents/chatkit']").first["src"]
    assert_match(%r{\Ahttp://plain\.example\.test/}, src)
    assert_includes response.headers["Content-Security-Policy"][/script-src[^;]*/], "http://plain.example.test"
  end

  test "a wildcard asset host is allowed and used for the setup script" do
    sign_in_with_workspace
    @configuration.chatkit_domain_key = "domain_pk_test"
    @ai.openai_api_key = "sk-test"

    with_asset_host("https://assets%d.example.test") do
      get recording_studio_agents.popup_path
    end

    assert_response :success
    src = css_select("script[src*='recording_studio_agents/chatkit']").first["src"]
    origin = src[%r{\Ahttps://assets[0-3]\.example\.test}]
    assert origin, src
    assert_includes response.headers["Content-Security-Policy"][/script-src[^;]*/], origin
  end

  test "the chatkit setup script is served as javascript" do
    sign_in_with_workspace
    @configuration.chatkit_domain_key = "domain_pk_test"
    @ai.openai_api_key = "sk-test"

    get recording_studio_agents.popup_path

    assert_response :success
    src = css_select("script[src*='recording_studio_agents/chatkit']").first["src"]
    refute_includes src, "://"
    get src

    assert_response :success
    assert_match(/javascript/, response.media_type)
  end

  test "a nonce enabled host still allows the chatkit asset" do
    sign_in_with_workspace
    @configuration.chatkit_domain_key = "domain_pk_test"
    @ai.openai_api_key = "sk-test"
    previous_generator = Rails.application.config.content_security_policy_nonce_generator
    previous_directives = Rails.application.config.content_security_policy_nonce_directives
    Rails.application.config.content_security_policy_nonce_generator = ->(*) { "popup-nonce" }
    Rails.application.config.content_security_policy_nonce_directives = %w[script-src]
    Rails.application.remove_instance_variable(:@app_env_config) if Rails.application.instance_variable_defined?(:@app_env_config)

    get recording_studio_agents.popup_path

    assert_response :success
    assert_select "script:not([src])", count: 0
    assert_select "script[src*='recording_studio_agents/chatkit']", count: 1
    policy = response.headers["Content-Security-Policy"]
    script_src = policy[/script-src[^;]*/]
    assert_includes script_src, "'self'"
    assert_includes script_src, "https://cdn.platform.openai.com"
    assert_includes script_src, "'nonce-popup-nonce'"
    refute_includes script_src, "unsafe-inline"
  ensure
    Rails.application.config.content_security_policy_nonce_generator = previous_generator
    Rails.application.config.content_security_policy_nonce_directives = previous_directives
    Rails.application.remove_instance_variable(:@app_env_config) if Rails.application.instance_variable_defined?(:@app_env_config)
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
    refute_includes policy, "unsafe-inline"
    policy
  end

  def with_asset_host(host)
    previous_action_host = Rails.application.config.action_controller.asset_host
    previous_host = Rails.application.config.asset_host
    previous_controller_host = ActionController::Base.asset_host
    Rails.application.config.action_controller.asset_host = host
    Rails.application.config.asset_host = host
    ActionController::Base.asset_host = host
    yield
  ensure
    Rails.application.config.action_controller.asset_host = previous_action_host
    Rails.application.config.asset_host = previous_host
    ActionController::Base.asset_host = previous_controller_host
  end

  def sign_in_with_workspace
    root = RecordingStudio.root_recording_for(Workspace.create!(name: "Popup #{SecureRandom.hex(4)}"))
    grant_edit(@user, root)
    sign_in @user
    root
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
