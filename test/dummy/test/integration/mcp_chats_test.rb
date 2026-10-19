# frozen_string_literal: true

require "test_helper"

class McpChatsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "mcp-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @alpha = workspace_root("Alpha")
    @zulu = workspace_root("Zulu")
    @alpha_access = grant_admin(@user, @alpha)
    grant_admin(@user, @zulu)
    @calls = []
    stub_agents
    @alpha_chat = create_chat(@alpha, "alpha hello", "alpha-key")
    @zulu_chat = create_chat(@zulu, "zulu hello", "zulu-key")
    @oauth_client = RecordingStudioOauth::OauthClient.create!(
      name: "MCP #{SecureRandom.hex(4)}",
      confidential: false,
      redirect_uris: ["http://127.0.0.1/callback"],
      api_key: "public"
    )
    @token = delegated_token(@alpha_access)
  end

  teardown do
    restore_agents
  end

  test "initialize tools list and a bearer tools call stay inside the granted workspace" do
    post_mcp("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "agents-test", version: "0.3.0" }
    })
    assert_response :success
    assert_equal "2025-06-18", JSON.parse(response.body).dig("result", "protocolVersion")

    post_mcp("tools/list")
    assert_response :success
    names = JSON.parse(response.body).dig("result", "tools").map { |tool| tool["name"] }
    assert_includes names, "agent_chats_list"
    assert_includes names, "agent_chats_create"
    assert_includes names, "agent_chats_read"
    assert_includes names, "agent_items_list"

    post_mcp("resources/list")
    assert_response :success
    uris = JSON.parse(response.body).dig("result", "resources").map { |resource| resource["uri"] }
    assert_includes uris, "skill://agent-chats/SKILL.md"

    post_mcp("tools/call", name: "agent_chats_list", arguments: {})
    assert_response :success
    payload = JSON.parse(response.body)
    ids = tool_payload(payload).fetch("chats").map { |chat| chat["id"] }

    assert_equal false, payload.dig("result", "isError")
    assert_equal [@alpha_chat.id], ids
    refute_includes ids, @zulu_chat.id
  end

  test "a bearer for one workspace cannot read or append another workspace chat" do
    post_mcp("tools/call", name: "agent_chats_read", arguments: { id: @zulu_chat.id })
    assert_equal true, JSON.parse(response.body).dig("result", "isError")

    post_mcp("tools/call", name: "agent_chats_append", arguments: {
      id: @zulu_chat.id, input: "nope", idempotency_key: "cross-root"
    })
    assert_equal true, JSON.parse(response.body).dig("result", "isError")
    assert_equal 0, RecordingStudioAgents::Item.where(idempotency_key: "cross-root").count

    post_mcp("tools/call", name: "agent_items_list", arguments: { id: @zulu_chat.id })
    assert_equal true, JSON.parse(response.body).dig("result", "isError")
  end

  private

  def workspace_root(prefix)
    RecordingStudio.root_recording_for(Workspace.create!(name: "#{prefix} #{SecureRandom.hex(4)}"))
  end

  def post_mcp(method, params = nil)
    body = { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method }
    body[:params] = params unless params.nil?
    post "/recording_studio_mcp", params: body.to_json, headers: {
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "Authorization" => "Bearer #{@token}"
    }
  end

  def tool_payload(payload)
    result = payload.fetch("result")
    return result.fetch("structuredContent") if result["structuredContent"].present?

    JSON.parse(result.dig("content", 0, "text"))
  end

  def delegated_token(access_recording)
    verifier = "V#{SecureRandom.urlsafe_base64(32)}".ljust(43, "a")
    approved = RecordingStudioOauth::Services::CreateOauthAuthorization.call(
      oauth_client: @oauth_client,
      manager_actor: @user,
      access_recording: access_recording,
      role: "edit",
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

  def create_chat(root, input, key)
    RecordingStudioAgents::Sessions::Create.call(
      parent_recording: root, root_recording: root, actor: @user, input: input, idempotency_key: key
    ).value!
  end

  def grant_admin(actor, recording)
    Current.actor = actor if defined?(Current)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    raise result.error.to_s unless result.success?

    result.value
  end

  def stub_agents
    test = self
    @original = {
      create_session: RecordingStudioAI::Agents.method(:create_session),
      send_input: RecordingStudioAI::Agents.method(:send_input)
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
  end

  def restore_agents
    return if @original.nil?

    @original.each do |name, original|
      RecordingStudioAI::Agents.define_singleton_method(name) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end
end
