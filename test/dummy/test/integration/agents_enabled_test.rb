# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AgentsEnabledTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  LAUNCHER_ID = RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID

  setup do
    @user = User.create!(email: "enabled-#{SecureRandom.hex(4)}@example.com", password: "Password") do |user|
      user.skip_confirmation!
    end
    sign_in @user
    workspace = Workspace.create!(name: "Enabled #{SecureRandom.hex(4)}")
    RecordingStudio.create_root_recording!(workspace, actor: @user)
    @configuration = RecordingStudioAgents.configuration
    @previous_enabled = @configuration.enabled
    @previous_launcher = @configuration.launcher
    @previous_actor = @configuration.request_actor
    @configuration.launcher = true
    @configuration.enabled = true
  end

  teardown do
    @configuration.enabled = @previous_enabled
    @configuration.launcher = @previous_launcher
    @configuration.request_actor = @previous_actor
    ActionController::Base.allow_forgery_protection = false
  end

  test "enabled false hides the launcher and the chat and answers every engine route with not found" do
    get root_path
    assert_response :success
    assert_select "##{LAUNCHER_ID}", count: 1

    get agent_chat_path
    assert_response :success
    assert chat_frame?(response.body), "expected the chat frame or the setup notice"

    @configuration.enabled = false
    @configuration.launcher = true
    @configuration.request_actor = ->(*) { raise "actor resolver ran" }

    get root_path
    assert_response :success
    assert_select "##{LAUNCHER_ID}", count: 0
    assert_select ".fp-floating-frame", count: 0

    get agent_chat_path
    assert_response :success
    refute chat_frame?(response.body)

    routes = engine_routes
    assert_includes routes.map(&:last), "/recording_studio_agents/popup"
    assert_includes routes.map(&:last), "/recording_studio_agents/chatkit"
    routes.each do |verb, path|
      process(verb, path)
      assert_response :not_found, "#{verb.upcase} #{path} returned #{response.status}"
    end
  end

  test "a lambda is read on each request" do
    open = true
    @configuration.enabled = ->(*) { open }

    get recording_studio_agents.popup_path
    assert_response :success

    open = false
    get recording_studio_agents.popup_path
    assert_response :not_found

    open = true
    get recording_studio_agents.popup_path
    assert_response :success
  end

  test "a chatkit post without a csrf token is not found when agents are off" do
    ActionController::Base.allow_forgery_protection = true
    path = "/recording_studio_agents/chatkit"

    @configuration.enabled = true
    post path, params: { type: "threads.create" }
    assert_response 422

    @configuration.enabled = false
    post path, params: { type: "threads.create" }
    assert_response :not_found
  end

  private

  def chat_frame?(body)
    body.include?("openai-chatkit") || body.include?("ChatKit setup")
  end

  def engine_routes
    RecordingStudioAgents::Engine.routes.routes.filter_map do |route|
      verb = route_verb(route)
      next if verb.blank?

      path = "/recording_studio_agents#{route.path.spec.to_s.sub('(.:format)', '')}"
      [verb, path]
    end
  end

  def route_verb(route)
    raw = route.verb
    raw = raw.source if raw.respond_to?(:source)
    raw.to_s.gsub(/[^A-Za-z|]/, "").split("|").first.to_s.downcase
  end
end
