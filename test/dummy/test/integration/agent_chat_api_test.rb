# frozen_string_literal: true

require "test_helper"

class AgentChatApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "api-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @alpha = workspace_root("Alpha")
    @other_root = workspace_root("Other")
    @alpha_access = grant_admin(@user, @alpha)
    grant_admin(@other, @other_root)
    @calls = []
    stub_agents
    @chat = create_chat(@alpha, @user, "alpha hello", "alpha-key")
    @foreign_chat = create_chat(@other_root, @other, "other hello", "other-key")
    @oauth_client = RecordingStudioOauth::OauthClient.create!(
      name: "API #{SecureRandom.hex(4)}",
      confidential: false,
      redirect_uris: [ "http://127.0.0.1/callback" ],
      api_key: "public"
    )
    @token = delegated_token(@alpha_access)
  end

  teardown do
    restore_agents
  end

  test "edit token can rename and close a chat over HTTP" do
    patch_chat(@chat.id, { title: "Launch plan" })
    assert_response :success, response.body
    payload = JSON.parse(response.body)

    assert_equal @chat.id, payload.fetch("id")
    assert_equal "Launch plan", payload.fetch("title")
    assert_equal "Launch plan", @chat.reload.recordable.title

    delete_chat(@chat.id)
    assert_response :success, response.body
    assert_equal({ "id" => @chat.id }, JSON.parse(response.body))
    assert_nil RecordingStudio::Recording.find_by(id: @chat.id)
  end

  test "missing bearer is unauthorized" do
    @token = nil
    patch_chat(@chat.id, { title: "Nope" })
    assert_response :unauthorized
    assert_equal "alpha hello", title_for(@chat)

    delete_chat(@chat.id)
    assert_response :unauthorized
    assert RecordingStudio::Recording.exists?(@chat.id)
  end

  test "view token cannot rename or close" do
    @token = delegated_token(@alpha_access, role: "view")
    patch_chat(@chat.id, { title: "Nope" })
    assert_response :forbidden
    assert_includes response.body, "not authorized"
    assert_equal "alpha hello", title_for(@chat)

    delete_chat(@chat.id)
    assert_response :forbidden
    assert_includes response.body, "not authorized"
    assert RecordingStudio::Recording.exists?(@chat.id)
  end

  test "another users chat is not reachable" do
    patch_chat(@foreign_chat.id, { title: "Stolen" })
    assert_response :not_found
    assert_equal "other hello", title_for(@foreign_chat)

    delete_chat(@foreign_chat.id)
    assert_response :not_found
    assert RecordingStudio::Recording.exists?(@foreign_chat.id)
  end

  private

  def title_for(recording)
    recording.reload.recordable.title
  end

  def patch_chat(id, params)
    request_chat(:patch, id, params)
  end

  def delete_chat(id)
    request_chat(:delete, id)
  end

  def request_chat(verb, id, params = nil)
    headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
    headers["Authorization"] = "Bearer #{@token}" if @token
    public_send(
      verb,
      "/recording_studio_api/api/v1/agent_chats/#{id}",
      params: params&.to_json,
      headers: headers
    )
  end

  def workspace_root(prefix)
    RecordingStudio.root_recording_for(Workspace.create!(name: "#{prefix} #{SecureRandom.hex(4)}"))
  end

  def create_chat(root, actor, input, key)
    RecordingStudioAgents::Sessions::Create.call(
      parent_recording: root, root_recording: root, actor: actor, input: input, idempotency_key: key, title: input
    ).value!
  end

  def grant_admin(actor, recording)
    Current.actor = actor if defined?(Current)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    raise result.error.to_s unless result.success?

    result.value
  end

  def delegated_token(access_recording, role: "edit")
    verifier = "V#{SecureRandom.urlsafe_base64(32)}".ljust(43, "a")
    approved = RecordingStudioOauth::Services::CreateOauthAuthorization.call(
      oauth_client: @oauth_client,
      manager_actor: @user,
      access_recording: access_recording,
      role: role,
      redirect_uri: "http://127.0.0.1/callback",
      code_challenge: RecordingStudioOauth::Pkce.s256_challenge(verifier),
      code_challenge_method: "S256"
    )
    raise approved.error unless approved.success?

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.value.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: verifier
    }
    assert_response :success, response.body
    JSON.parse(response.body).fetch("access_token")
  end

  def stub_agents
    test = self
    @original = {
      create_session: RecordingStudioAI::Agents.method(:create_session),
      send_input: RecordingStudioAI::Agents.method(:send_input),
      delete_session: RecordingStudioAI::Agents.method(:delete_session)
    }
    RecordingStudioAI::Agents.define_singleton_method(:create_session) do |**kwargs|
      test.instance_variable_get(:@calls) << kwargs
      RecordingStudioAI::Agents::Session.new(
        provider: :openai, provider_session_id: "sess_#{test.instance_variable_get(:@calls).size}",
        model: "gpt-6-astra", profile: "medium", status: "in_progress"
      )
    end
    RecordingStudioAI::Agents.define_singleton_method(:send_input) do |**kwargs|
      kwargs.fetch(:session)
    end
    RecordingStudioAI::Agents.define_singleton_method(:delete_session) do |**|
      true
    end
  end

  def restore_agents
    return if @original.nil?

    @original.each do |name, original|
      RecordingStudioAI::Agents.define_singleton_method(name, original)
    end
  end
end
