# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpChatsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup do
    @user = User.create!(email: "mcp-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @alpha = workspace_root("Alpha")
    @zulu = workspace_root("Zulu")
    @alpha_access = grant_admin(@user, @alpha)
    @zulu_access = grant_admin(@user, @zulu)
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

    item = RecordingStudioAgents::Item.find_by!(recording_id: @zulu_chat.id)
    post_mcp("tools/call", name: "agent_items_read", arguments: { id: @zulu_chat.id, item_id: item.id })
    assert_equal true, JSON.parse(response.body).dig("result", "isError")
  end

  test "a cross-workspace key is a conflict over the bearer" do
    key = "clash-#{SecureRandom.hex(4)}"
    create_chat(@zulu, "taken", key)
    add_global_binding_index
    RecordingStudioAgents::Sessions::GlobalKey.reset_index_cache!
    before = @calls.size

    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "hello", idempotency_key: key, title: "Clash"
    })
    message = JSON.parse(response.body).dig("result", "content", 0, "text").to_s

    assert_equal true, JSON.parse(response.body).dig("result", "isError")
    assert_includes message, "conflict"
    assert_equal before, @calls.size
  ensure
    drop_global_binding_index
    RecordingStudioAgents::Sessions::GlobalKey.reset_index_cache!
  end

  test "create stores an instructions override from the tool call" do
    with_instruction_settings(override: :edit) do
      post_mcp("tools/call", name: "agent_chats_create", arguments: {
        input: "hello", idempotency_key: "instr-#{SecureRandom.hex(4)}", instructions: "Be terse."
      })
      payload = JSON.parse(response.body)
      recording = RecordingStudio::Recording.find(tool_payload(payload).fetch("id"))

      assert_equal false, payload.dig("result", "isError"), response.body
      assert_equal "Answer in one sentence.\n\nBe terse.", recording.recordable.instructions
      assert_equal "Answer in one sentence.\n\nBe terse.", @calls.last[:instructions]
    end
  end

  test "a blank instructions value stores the host default" do
    before = @calls.size
    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "hello", idempotency_key: "blank-#{SecureRandom.hex(4)}", instructions: "  \n "
    })
    payload = JSON.parse(response.body)
    recording = RecordingStudio::Recording.find(tool_payload(payload).fetch("id"))

    assert_equal false, payload.dig("result", "isError"), response.body
    assert_equal "Answer in one sentence.", recording.recordable.instructions
    assert_equal before + 1, @calls.size
  end

  test "a real override is rejected when the host has not opted in" do
    before = @calls.size
    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "hello", idempotency_key: "none-#{SecureRandom.hex(4)}", instructions: "Be terse."
    })

    assert_tool_error("instructions overrides are disabled")
    assert_equal before, @calls.size
  end

  test "an edit token cannot override when only admins may" do
    before = @calls.size

    with_instruction_settings(override: :admin) do
      post_mcp("tools/call", name: "agent_chats_create", arguments: {
        input: "hello", idempotency_key: "edit-admin-#{SecureRandom.hex(4)}", instructions: "Be terse."
      })

      assert_tool_error("not authorized")
      assert_equal before, @calls.size
    end
  end

  test "an admin token can append an override when the host opts in" do
    @token = delegated_token(@alpha_access, role: "admin")

    with_instruction_settings(override: :admin) do
      post_mcp("tools/call", name: "agent_chats_create", arguments: {
        input: "hello", idempotency_key: "admin-#{SecureRandom.hex(4)}", instructions: "Be terse."
      })
      payload = JSON.parse(response.body)
      recording = RecordingStudio::Recording.find(tool_payload(payload).fetch("id"))

      assert_equal false, payload.dig("result", "isError"), response.body
      assert_equal "Answer in one sentence.\n\nBe terse.", recording.recordable.instructions
    end
  end

  test "a non-string instructions value is rejected" do
    before = @calls.size
    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "hello", idempotency_key: "type-#{SecureRandom.hex(4)}", instructions: { tone: "terse" }
    })

    assert_tool_error("instructions must be a string")
    assert_equal before, @calls.size
  end

  test "instructions longer than 4000 characters are rejected" do
    before = @calls.size
    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "hello", idempotency_key: "long-#{SecureRandom.hex(4)}", instructions: "a" * 4001
    })

    assert_tool_error("instructions must be at most 4000 characters")
    assert_equal before, @calls.size
  end

  test "the create contract caps instructions at 4000 characters" do
    contract = RecordingStudioApi.registered_endpoint(:agent_chats_create).input_contract

    assert_equal 4000, contract.as_json.dig(:fields, :instructions, :maxLength)
  end

  test "the same create key opens a chat in each workspace over the bearer" do
    key = "shared-#{SecureRandom.hex(4)}"
    alpha_id = create_over_mcp(key)
    @token = delegated_token(@zulu_access)
    zulu_id = create_over_mcp(key)

    refute_equal alpha_id, zulu_id
    roots = RecordingStudioAgents::Binding.where(create_idempotency_key: key).pluck(:root_recording_id)
    assert_equal [@alpha.id, @zulu.id].sort, roots.sort
  end

  test "a view-only token cannot create or append" do
    @token = delegated_token(@alpha_access, role: "view")
    before = RecordingStudioAgents::Binding.count

    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "nope", idempotency_key: "view-only", title: "Nope"
    })
    assert_authorization_error

    post_mcp("tools/call", name: "agent_chats_append", arguments: {
      id: @alpha_chat.id, input: "nope", idempotency_key: "view-only-append"
    })
    assert_authorization_error
    assert_equal before, RecordingStudioAgents::Binding.count
    assert_equal 0, RecordingStudioAgents::Item.where(idempotency_key: "view-only-append").count
  end

  test "a bearer ignores the switcher cookie and a root argument" do
    sign_in @user
    switch_to(@zulu)

    post_mcp("tools/call", name: "agent_chats_list", arguments: {})
    ids = tool_payload(JSON.parse(response.body)).fetch("chats").map { |chat| chat["id"] }

    assert_equal [@alpha_chat.id], ids
    refute_includes ids, @zulu_chat.id

    post_mcp("tools/call", name: "agent_chats_list", arguments: { root_recording_id: @zulu.id })
    rejected = JSON.parse(response.body)
    message = rejected.dig("result", "content", 0, "text").to_s

    assert_equal true, rejected.dig("result", "isError")
    assert_includes message, "Invalid input"
    refute_includes message, @zulu_chat.id
  end

  test "parent limits list and create to that page" do
    page = @alpha.record(Page, actor: @user) { |record| record.title = "Press kit" }
    key = "page-#{SecureRandom.hex(4)}"

    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "on the page", idempotency_key: key, title: "On the page", parent: page.id
    })
    payload = JSON.parse(response.body)
    created_id = tool_payload(payload).fetch("id")
    recording = RecordingStudio::Recording.find(created_id)

    assert_equal false, payload.dig("result", "isError"), response.body
    assert_equal page.id, recording.parent_recording_id

    post_mcp("tools/call", name: "agent_chats_list", arguments: { parent: page.id })
    scoped_ids = tool_payload(JSON.parse(response.body)).fetch("chats").map { |chat| chat["id"] }

    assert_equal [created_id], scoped_ids

    post_mcp("tools/call", name: "agent_chats_list", arguments: {})
    all_ids = tool_payload(JSON.parse(response.body)).fetch("chats").map { |chat| chat["id"] }

    assert_includes all_ids, created_id
    assert_includes all_ids, @alpha_chat.id
    refute_includes all_ids, @zulu_chat.id
  end

  test "a parent in another workspace is rejected" do
    page = @zulu.record(Page, actor: @user) { |record| record.title = "Elsewhere" }
    before = RecordingStudioAgents::Binding.count

    post_mcp("tools/call", name: "agent_chats_list", arguments: { parent: page.id })
    assert_tool_error("page was not found")

    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "nope", idempotency_key: "cross-page-#{SecureRandom.hex(4)}", parent: page.id
    })
    assert_tool_error("page was not found")
    assert_equal before, RecordingStudioAgents::Binding.count
  end

  test "a parent the grant cannot view is rejected" do
    page = @alpha.record(Page, actor: @user) { |record| record.title = "Detached" }
    page.update_columns(parent_recording_id: @zulu.id)
    before = RecordingStudioAgents::Binding.count

    post_mcp("tools/call", name: "agent_chats_list", arguments: { parent: page.id })
    assert_tool_error("not authorized")

    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "nope", idempotency_key: "hidden-#{SecureRandom.hex(4)}", parent: page.id
    })
    assert_tool_error("not authorized")
    assert_equal before, RecordingStudioAgents::Binding.count
    assert_equal @alpha.id, page.reload.root_recording_id
  end

  test "a repeated create key ignores a different parent" do
    page = @alpha.record(Page, actor: @user) { |record| record.title = "Press kit" }
    other = @alpha.record(Page, actor: @user) { |record| record.title = "Other page" }
    key = "replay-parent-#{SecureRandom.hex(4)}"

    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "on the page", idempotency_key: key, title: "On the page", parent: page.id
    })
    created_id = tool_payload(JSON.parse(response.body)).fetch("id")

    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "on the page", idempotency_key: key, title: "Moved", parent: other.id
    })
    replay = JSON.parse(response.body)

    assert_equal false, replay.dig("result", "isError"), response.body
    assert_equal created_id, tool_payload(replay).fetch("id")
    assert_equal page.id, RecordingStudio::Recording.find(created_id).parent_recording_id
  end

  test "a non-string parent is not found" do
    post_mcp("tools/call", name: "agent_chats_list", arguments: { parent: { id: @alpha.id } })
    assert_tool_error("page was not found")

    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "nope", idempotency_key: "hash-parent-#{SecureRandom.hex(4)}", parent: ["not-a-page"]
    })
    assert_tool_error("page was not found")
  end

  test "a folder parent cannot hold a chat" do
    folder = @alpha.record(Folder, actor: @user) { |record| record.name = "Notes" }

    post_mcp("tools/call", name: "agent_chats_list", arguments: { parent: folder.id })
    assert_tool_error("page cannot hold a chat")

    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "nope", idempotency_key: "folder-parent-#{SecureRandom.hex(4)}", parent: folder.id
    })
    assert_tool_error("page cannot hold a chat")
  end

  test "a trashed page parent is not found" do
    page = @alpha.record(Page, actor: @user) { |record| record.title = "Gone" }
    page.update_columns(trashed_at: Time.current)

    post_mcp("tools/call", name: "agent_chats_list", arguments: { parent: page.id })
    assert_tool_error("page was not found")
  end

  test "list and create contracts accept an optional parent" do
    list = RecordingStudioApi.registered_endpoint(:agent_chats_list).input_contract.as_json
    created = RecordingStudioApi.registered_endpoint(:agent_chats_create).input_contract.as_json

    assert_equal false, list.dig(:fields, :parent, :required)
    assert_equal false, created.dig(:fields, :parent, :required)
  end

  test "a request with both a session and a bearer uses the grant workspace" do
    sign_in @user
    switch_to(@zulu)

    post_mcp("tools/call", name: "agent_chats_list", arguments: {})
    ids = tool_payload(JSON.parse(response.body)).fetch("chats").map { |chat| chat["id"] }

    assert_equal [@alpha_chat.id], ids
    refute_includes ids, @zulu_chat.id
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

  def with_instruction_settings(override:)
    configuration = RecordingStudioAgents.configuration
    previous = configuration.instructions_override
    configuration.instructions_override = override
    yield
  ensure
    configuration.instructions_override = previous
  end

  def assert_tool_error(fragment)
    payload = JSON.parse(response.body)
    message = payload.dig("result", "content", 0, "text").to_s

    assert_equal true, payload.dig("result", "isError")
    assert_includes message, fragment
  end

  def assert_authorization_error
    payload = JSON.parse(response.body)
    message = payload.dig("result", "content", 0, "text").to_s

    assert_equal true, payload.dig("result", "isError")
    assert_includes message, "not authorized"
  end

  def tool_payload(payload)
    result = payload.fetch("result")
    return result.fetch("structuredContent") if result["structuredContent"].present?

    JSON.parse(result.dig("content", 0, "text"))
  end

  def create_over_mcp(key)
    post_mcp("tools/call", name: "agent_chats_create", arguments: {
      input: "shared", idempotency_key: key, title: "Shared"
    })
    payload = JSON.parse(response.body)
    assert_equal false, payload.dig("result", "isError"), response.body
    tool_payload(payload).fetch("id")
  end

  def switch_to(root)
    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: { root_recording_id: root.id, return_to: "/" }
    }
    assert_response :redirect
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

  def add_global_binding_index
    connection = ActiveRecord::Base.connection
    return if connection.index_exists?(
      :recording_studio_agents_bindings, :create_idempotency_key, name: "index_rs_agents_bindings_on_create_key"
    )

    connection.add_index(
      :recording_studio_agents_bindings, :create_idempotency_key,
      unique: true, name: "index_rs_agents_bindings_on_create_key"
    )
  end

  def drop_global_binding_index
    connection = ActiveRecord::Base.connection
    return unless connection.index_exists?(
      :recording_studio_agents_bindings, :create_idempotency_key, name: "index_rs_agents_bindings_on_create_key"
    )

    connection.remove_index :recording_studio_agents_bindings, name: "index_rs_agents_bindings_on_create_key"
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
      RecordingStudioAI::Agents.define_singleton_method(name, original)
    end
  end
end
