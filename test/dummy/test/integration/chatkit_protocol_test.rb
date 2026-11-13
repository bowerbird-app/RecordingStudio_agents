# frozen_string_literal: true

require "test_helper"

class ChatkitProtocolTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "chatkit-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @root = RecordingStudio.root_recording_for(Workspace.create!(name: "Chat #{SecureRandom.hex(4)}"))
    @other_root = RecordingStudio.root_recording_for(Workspace.create!(name: "Other #{SecureRandom.hex(4)}"))
    grant_edit(@user, @root)
    @calls = Hash.new { |calls, name| calls[name] = [] }
    @stream = [event("message_completed", text: "Saved reply"), event("turn_completed")]
    @recovered = []
    @pending_calls = []
    @continuation = []
    @configuration = RecordingStudioAgents.configuration
    @previous_mcp_tools = @configuration.mcp_tools
    @previous_actor = @configuration.request_actor
    @previous_root = @configuration.request_root
    @configuration.request_actor = ->(*) { @user }
    @configuration.request_root = ->(*) { @root }
    stub_agents
  end

  teardown do
    if @configuration
      @configuration.request_actor = @previous_actor
      @configuration.request_root = @previous_root
      @configuration.mcp_tools = @previous_mcp_tools if @previous_mcp_tools
    end
    restore_agents
  end

  test "create stores the host default instructions" do
    events = stream_events(create_body("hello"))
    recording = RecordingStudio::Recording.find(events.first.dig("thread", "id"))

    assert_equal with_safety_preamble("Answer in one sentence."), recording.recordable.instructions
  end

  test "threads.create rejects instructions" do
    result = call_server("threads.create", create_params("hello").merge(instructions: "Be terse."))

    assert_equal 400, result.status
    assert_equal "ChatKit does not accept instructions", result.body[:message]
    assert_empty @calls[:create_session]
  end

  test "threads.create rejects blank non-string and too-long instructions" do
    ["  ", { tone: "terse" }, "a" * 4001].each do |instructions|
      result = call_server("threads.create", create_params("hello").merge(instructions: instructions))

      assert_equal 400, result.status
      assert_equal "ChatKit does not accept instructions", result.body[:message]
    end

    assert_empty @calls[:create_session]
  end

  test "create streams the saved first turn and ignores client metadata ids" do
    events = stream_events(create_body("hello", root_id: @other_root.id))

    assert_equal %w[thread.created thread.item.done stream_options thread.item.done], events.map { |event| event["type"] }
    assert_equal "Saved reply", events.last.dig("item", "content", 0, "text")
    recording = RecordingStudio::Recording.find(events.first.dig("thread", "id"))
    assert_equal @root, recording.root_recording
    assert_equal 1, RecordingStudioAgents::Item.where(recording: recording, role: "assistant").count
    assert_equal 1, @calls[:create_session].size
    assert_equal @root, @calls[:create_session].first[:root_recording]
    assert_empty @calls[:recover]
  end

  test "text deltas become chatkit text delta events" do
    @stream = [event("text_delta", text_delta: "Hi"), event("message_completed", text: "Hi"), event("turn_completed")]

    events = stream_events(create_body("hello"))
    delta = events.find { |event| event.dig("update", "type") == "assistant_message.content_part.text_delta" }

    assert_equal "Hi", delta.dig("update", "delta")
    assert_equal "thread.item.added", events.find { |event| event["type"] == "thread.item.added" }["type"]
  end

  test "a follow up stays on the same session" do
    created = stream_events(create_body("hello"))
    thread_id = created.first.dig("thread", "id")

    follow = stream_events(message_body(thread_id, "again"))

    assert_equal "thread.item.done", follow.first["type"]
    assert_equal 1, @calls[:create_session].size
    assert_equal 1, @calls[:send_input].size
    assert_equal thread_id, @calls[:send_input].first[:context_recording].id
  end

  test "a new chat sends workspace tools and leaves out chat tools" do
    stream_events(create_body("hello"))
    tools = @calls[:create_session].first.fetch(:tools)
    names = tools.map { |tool| tool[:name] }

    assert_includes names, "show"
    assert_includes names, "update"
    assert_equal "function", tools.first[:type]
    assert_equal "object", tools.first[:parameters]["type"]
    refute names.any? { |name| name.start_with?("agent_chats_", "agent_items_") }
  end

  test "mcp tools can be read only or off" do
    @configuration.mcp_tools = :read
    stream_events(create_body("hello"))
    names = @calls[:create_session].first.fetch(:tools).map { |tool| tool[:name] }

    assert_includes names, "show"
    refute_includes names, "update"

    @configuration.mcp_tools = :off
    stream_events(create_body("again"))

    refute @calls[:create_session].last.key?(:tools)
  end

  test "mcp absent sends no tools" do
    tools = RecordingStudioAgents::Mcp::ChatTools
    original = tools.method(:installed?)
    tools.define_singleton_method(:installed?) { false }
    stream_events(create_body("hello"))

    refute @calls[:create_session].first.key?(:tools)
  ensure
    tools.define_singleton_method(:installed?) { original.call }
  end

  test "a dropped stream answers pending tool calls" do
    call = tool_call
    @stream = []
    @stream_result = tool_turn([call])
    @continuation = [event("message_completed", text: "Used the tool"), event("turn_completed")]

    events = stream_events(create_body("hello"))

    assert_equal "Used the tool", events.last.dig("item", "content", 0, "text")
    submitted = @calls[:submit_tool_results].first.fetch(:results).first
    assert_equal call.call_id, submitted[:call_id]
    assert_equal call.provider_turn_id, submitted[:turn_id]
    assert_equal 1, @calls[:submit_tool_results].size
  end

  test "pending tool calls on recovery are answered" do
    call = tool_call
    @stream = []
    @pending_calls = [call]
    @continuation = [event("message_completed", text: "Recovered"), event("turn_completed")]

    events = stream_events(create_body("hello"))

    assert_equal "Recovered", events.last.dig("item", "content", 0, "text")
    assert_equal call.call_id, @calls[:submit_tool_results].first.fetch(:results).first[:call_id]
    assert_equal 1, @calls[:recover].size
  end

  test "a timed out tool result rereads pending calls before it retries" do
    call = tool_call
    @stream = []
    @stream_result = tool_turn([call])
    @pending_calls = [call]
    @submit_error = timeout_failure
    @continuation = [event("message_completed", text: "Retried"), event("turn_completed")]

    events = stream_events(create_body("hello"))

    assert_equal "Retried", events.last.dig("item", "content", 0, "text")
    assert_equal 2, @calls[:submit_tool_results].size
    assert_equal [call.call_id, call.call_id], @calls[:submit_tool_results].map { |submit|
      submit[:results].first[:call_id]
    }
    assert_operator @calls[:recover].size, :>=, 1
  end

  test "a turn dispatches eight tool rounds and refuses the next without a ninth dispatch" do
    dispatched = []
    with_dispatcher(dispatched) do
      @stream = []
      @stream_result = tool_turn([tool_call("round-0")])
      @submit_script = (1..8).map { |index| tool_turn([tool_call("round-#{index}")]) }

      stream_events(create_body("hello"))
    end

    assert_equal 8, dispatched.size
    assert_equal 9, @calls[:submit_tool_results].size
    refusal = @calls[:submit_tool_results].last.fetch(:results).first
    assert_equal "round-8", refusal[:call_id]
    assert_equal "too many tool calls", refusal[:error]
    assert_empty @calls[:cancel]
  end

  test "tool calls still waiting after the cap cancel the run" do
    dispatched = []
    events = nil
    with_dispatcher(dispatched) do
      @stream = []
      @stream_result = tool_turn([tool_call("round-0")])
      @submit_script = (1..8).map { |index| tool_turn([tool_call("round-#{index}")]) }
      @submit_script << tool_turn([tool_call("still-waiting")])

      events = stream_events(create_body("hello"))
    end

    assert_equal 8, dispatched.size
    assert_equal 1, @calls[:cancel].size
    failure = events.find { |event| event["type"] == "error" }
    assert_equal "The response failed.", failure["message"]
    refute @calls[:submit_tool_results].last.fetch(:results).any? { |result| result[:call_id] == "still-waiting" }
  end

  test "a timed out tool result does not retry a call that is no longer pending" do
    call = tool_call
    @stream = []
    @stream_result = tool_turn([call])
    @pending_calls = []
    @submit_error = timeout_failure
    @next_stream = [event("message_completed", text: "Already posted"), event("turn_completed")]

    events = stream_events(create_body("hello"))

    assert_equal "Already posted", events.last.dig("item", "content", 0, "text")
    assert_equal 1, @calls[:submit_tool_results].size
    assert_equal 2, @calls[:stream].size
  end

  test "an empty stream reads the saved first turn" do
    @stream = []
    @recovered = [RecordingStudioAI::Agents::Item.new(id: "saved", role: "assistant", text: "From the saved turn", status: "done")]

    events = stream_events(create_body("hello"))

    assert_equal "From the saved turn", events.last.dig("item", "content", 0, "text")
    assert_equal 1, @calls[:recover].size
  end

  test "an unsupported operation is a protocol error" do
    result = call_server("threads.retry_after_item", { thread_id: "thr_x", item_id: "msg_x" })

    refute result.streaming?
    assert_equal 400, result.status
    assert_equal "unsupported operation", result.body[:message]
    assert_empty @calls[:create_session]
  end

  test "a thread from another root is not found and is not deleted" do
    thread_id = stream_events(create_body("hello")).first.dig("thread", "id")

    missing = RecordingStudioAgents::ChatKit::Server.call(
      { type: "threads.get_by_id", params: { thread_id: thread_id } }.to_json,
      actor: @user, root_recording: @other_root
    )
    deleted = RecordingStudioAgents::ChatKit::Server.call(
      { type: "threads.delete", params: { thread_id: thread_id } }.to_json,
      actor: @user, root_recording: @other_root
    )

    assert_equal 404, missing.status
    assert_equal 404, deleted.status
    assert_empty @calls[:delete_session]
    assert RecordingStudio::Recording.exists?(thread_id)
  end

  test "an actor without access is refused before a provider call" do
    stranger = User.create!(email: "stranger-#{SecureRandom.hex(4)}@example.com", password: "Password")

    result = RecordingStudioAgents::ChatKit::Server.call(
      create_body("hello"), actor: stranger, root_recording: @root
    )

    assert_equal 403, result.status
    assert_empty @calls[:create_session]
  end

  test "list update and delete use the session recording" do
    thread_id = stream_events(create_body("hello")).first.dig("thread", "id")
    listed = call_server("threads.list", { limit: 10 })
    renamed = call_server("threads.update", { thread_id: thread_id, title: "Launch plan" })
    items = call_server("items.list", { thread_id: thread_id, order: "asc" })
    call_server("threads.delete", { thread_id: thread_id })

    assert_equal [thread_id], listed.body[:data].map { |thread| thread[:id] }
    assert_equal "Launch plan", renamed.body[:title]
    assert_equal %w[user assistant], items.body[:data].map { |item| item[:type].sub("_message", "") }
    refute RecordingStudio::Recording.exists?(thread_id)
    assert_equal 1, @calls[:delete_session].size
  end

  test "cancel calls the agent api and leaves the chat" do
    before = RecordingStudioAgents::Binding.count
    result = call_server("threads.create", create_params("hello"))

    result.cancel!

    assert_equal 1, @calls[:cancel].size
    assert_equal before + 1, RecordingStudioAgents::Binding.count
  end

  test "a page recording parents the new chat and the catalog hides the others" do
    page = @root.record(Page, actor: @user) { |record| record.title = "Press kit" }
    workspace_id = stream_events(create_body("workspace hello")).first.dig("thread", "id")

    page_events = RecordingStudioAgents::ChatKit::Server.call(
      create_body("page hello"), actor: @user, root_recording: @root, page_recording: page
    ).each.map { |json| JSON.parse(json) }
    page_id = page_events.first.dig("thread", "id")
    scoped = RecordingStudioAgents::ChatKit::Catalog.new(@user, @root, page_recording: page)
    listed = scoped.list_threads("limit" => 20)
    whole = RecordingStudioAgents::ChatKit::Catalog.new(@user, @root).list_threads("limit" => 20)

    assert_equal page, RecordingStudio::Recording.find(page_id).parent_recording
    assert_equal [page_id], listed[:data].map { |thread| thread[:id] }
    assert_equal [page_id, workspace_id].sort, whole[:data].map { |thread| thread[:id] }.sort
    missing = assert_raises(RecordingStudioAgents::ChatKit::ProtocolError) { scoped.find!(workspace_id) }
    assert_equal 404, missing.status
  end

  test "the endpoint scopes list and create when page_recording_id is present" do
    page = @root.record(Page, actor: @user) { |record| record.title = "Press kit" }
    workspace_id = stream_events(create_body("workspace hello")).first.dig("thread", "id")

    post chatkit_path(page.id), params: { type: "threads.create", params: create_params("page hello") }, as: :json
    page_id = created_thread_id

    listed = chatkit_json("threads.list", { "limit" => 20 }, page.id)
    whole = chatkit_json("threads.list", { "limit" => 20 })

    assert_equal page, RecordingStudio::Recording.find(page_id).parent_recording
    assert_equal [page_id], listed.fetch("data").map { |thread| thread["id"] }
    assert_equal [page_id, workspace_id].sort, whole.fetch("data").map { |thread| thread["id"] }.sort
  end

  test "a cross workspace page id is not found" do
    grant_edit(@user, @other_root)
    page = @other_root.record(Page, actor: @user) { |record| record.title = "Elsewhere" }

    listed = chatkit_json("threads.list", { "limit" => 20 }, page.id)

    assert_equal 404, listed.fetch("http_status")
    assert_equal "page was not found", listed.fetch("message")
  end

  test "a page inside the workspace that the actor cannot view is rejected" do
    page = @root.record(Page, actor: @user) { |record| record.title = "Press kit" }
    stranger = User.create!(email: "page-stranger-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @configuration.request_actor = ->(*) { stranger }

    listed = chatkit_json("threads.list", { "limit" => 20 }, page.id)

    assert_equal 403, listed.fetch("http_status")
    assert_equal "actor cannot access this recording", listed.fetch("message")
  end

  test "a folder cannot parent a chat" do
    folder = @root.record(Folder, actor: @user) { |record| record.name = "Notes" }

    listed = chatkit_json("threads.list", { "limit" => 20 }, folder.id)

    assert_equal 422, listed.fetch("http_status")
    assert_equal "page cannot hold a chat", listed.fetch("message")
  end

  test "a present non-string page id is not found" do
    post "/recording_studio_agents/chatkit?page_recording_id[]=not-a-page",
         params: { type: "threads.list", params: { limit: 20 } }, as: :json
    listed = JSON.parse(response.body).merge("http_status" => response.status)

    assert_equal 404, listed.fetch("http_status")
    assert_equal "page was not found", listed.fetch("message")
  end

  test "a hash page id is not found" do
    post "/recording_studio_agents/chatkit?page_recording_id[id]=not-a-page",
         params: { type: "threads.list", params: { limit: 20 } }, as: :json
    listed = JSON.parse(response.body).merge("http_status" => response.status)

    assert_equal 404, listed.fetch("http_status")
    assert_equal "page was not found", listed.fetch("message")
  end

  test "a trashed page is not found" do
    page = @root.record(Page, actor: @user) { |record| record.title = "Press kit" }
    page.update_columns(trashed_at: Time.current)

    listed = chatkit_json("threads.list", { "limit" => 20 }, page.id)

    assert_equal 404, listed.fetch("http_status")
    assert_equal "page was not found", listed.fetch("message")
  end

  test "a view-only actor cannot create a page chat" do
    page = @root.record(Page, actor: @user) { |record| record.title = "Press kit" }
    viewer = User.create!(email: "viewer-#{SecureRandom.hex(4)}@example.com", password: "Password")
    grant_role(viewer, @root, "view")
    @configuration.request_actor = ->(*) { viewer }

    listed = chatkit_json("threads.create", create_params("hello"), page.id)

    assert_equal 403, listed.fetch("http_status")
    assert_empty @calls[:create_session]
  end

  test "another page id cannot read or continue that page's chat" do
    page = @root.record(Page, actor: @user) { |record| record.title = "Press kit" }
    other = @root.record(Page, actor: @user) { |record| record.title = "Other page" }
    thread_id = RecordingStudioAgents::ChatKit::Server.call(
      create_body("page hello"), actor: @user, root_recording: @root, page_recording: page
    ).each.map { |json| JSON.parse(json) }.first.dig("thread", "id")

    shown = chatkit_json("threads.get_by_id", { "thread_id" => thread_id }, other.id)
    items = chatkit_json("items.list", { "thread_id" => thread_id }, other.id)
    added = chatkit_json("threads.add_user_message", create_params("again").merge("thread_id" => thread_id), other.id)

    assert_equal 404, shown.fetch("http_status")
    assert_equal 404, items.fetch("http_status")
    assert_equal 404, added.fetch("http_status")
    assert_equal 0, @calls[:send_input].size
  end

  test "a page chat is refused after page access is revoked" do
    page = @root.record(Page, actor: @user) { |record| record.title = "Press kit" }
    reader = User.create!(email: "reader-#{SecureRandom.hex(4)}@example.com", password: "Password")
    access = grant_role(reader, @root, "view")
    thread_id = RecordingStudioAgents::ChatKit::Server.call(
      create_body("page hello"), actor: @user, root_recording: @root, page_recording: page
    ).each.map { |json| JSON.parse(json) }.first.dig("thread", "id")
    @configuration.request_actor = ->(*) { reader }

    shown = chatkit_json("threads.get_by_id", { "thread_id" => thread_id }, page.id)
    access.update_columns(trashed_at: Time.current)
    refused = chatkit_json("threads.get_by_id", { "thread_id" => thread_id }, page.id)

    assert_equal 200, shown.fetch("http_status")
    assert_equal 403, refused.fetch("http_status")
  end

  test "a page id that is not a uuid is not found" do
    listed = chatkit_json("threads.list", { "limit" => 20 }, "not-a-page")

    assert_equal 404, listed.fetch("http_status")
    assert_equal "page was not found", listed.fetch("message")
  end

  test "the endpoint streams server sent events for the signed in root" do
    post "/recording_studio_agents/chatkit",
         params: { type: "threads.create", params: create_params("hello"), metadata: { root_recording_id: @other_root.id } },
         as: :json

    assert_response :success
    assert_includes response.media_type, "text/event-stream"
    assert_includes response.body, "thread.created"
    assert_includes response.body, "Saved reply"
  end

  private

  def chatkit_path(page_id = nil)
    path = "/recording_studio_agents/chatkit"
    return path if page_id.blank?

    "#{path}?#{RecordingStudioAgents::ScopedParent::QUERY_PARAM}=#{page_id}"
  end

  def chatkit_json(type, params, page_id = nil)
    post chatkit_path(page_id), params: { type: type, params: params }, as: :json
    JSON.parse(response.body).merge("http_status" => response.status)
  end

  def created_thread_id
    response.body.each_line do |line|
      next unless line.start_with?("data: ")

      payload = JSON.parse(line.delete_prefix("data: ").strip)
      return payload.dig("thread", "id") if payload["type"] == "thread.created"
    end
    flunk "thread.created was missing"
  end

  def stream_events(raw)
    result = RecordingStudioAgents::ChatKit::Server.call(raw, actor: @user, root_recording: @root)
    assert result.streaming?
    result.each.map { |json| JSON.parse(json) }
  end

  def call_server(type, params)
    RecordingStudioAgents::ChatKit::Server.call(
      { type: type, params: params }.to_json, actor: @user, root_recording: @root
    )
  end

  def create_body(text, root_id: nil, instructions: nil)
    params = create_params(text)
    params[:instructions] = instructions if instructions
    { type: "threads.create", params: params, metadata: { root_recording_id: root_id } }.to_json
  end

  def create_params(text)
    { input: { content: [{ type: "input_text", text: text }], attachments: [], inference_options: {} } }
  end

  def message_body(thread_id, text)
    {
      type: "threads.add_user_message",
      params: create_params(text).merge(thread_id: thread_id),
      metadata: { thread_id: @other_root.id }
    }.to_json
  end

  def grant_edit(actor, recording)
    grant_role(actor, recording, "edit")
  end

  def grant_role(actor, recording, role)
    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(recording).record(
        RecordingStudio::Access, actor: actor, parent_recording: recording
      ) do |access|
        access.actor = actor
        access.role = role
      end
    end
  end

  def stub_agents
    @original_agents = {}
    helper = self
    {
      create_session: ->(**kwargs) { helper.send(:record_create, kwargs) },
      send_input: ->(**kwargs) { helper.send(:record_send, kwargs) },
      delete_session: ->(**kwargs) { helper.send(:record_delete, kwargs) },
      cancel: ->(**kwargs) { helper.send(:record_cancel, kwargs) },
      recover: ->(**kwargs) { helper.send(:record_recover, kwargs) },
      stream: ->(**kwargs, &block) { helper.send(:record_stream, kwargs, block) },
      submit_tool_results: ->(**kwargs, &block) { helper.send(:record_submit, kwargs, block) }
    }.each do |name, implementation|
      remember_agent(name)
      RecordingStudioAI::Agents.define_singleton_method(name, &implementation)
    end
  end

  def record_create(kwargs)
    @calls[:create_session] << kwargs
    hosted("sess_#{@calls[:create_session].size}")
  end

  def record_send(kwargs)
    @calls[:send_input] << kwargs
    kwargs.fetch(:session)
  end

  def record_delete(kwargs)
    @calls[:delete_session] << kwargs
    kwargs.fetch(:session)
  end

  def record_cancel(kwargs)
    @calls[:cancel] << kwargs
    kwargs.fetch(:session)
  end

  def record_recover(kwargs)
    @calls[:recover] << kwargs
    RecordingStudioAI::Agents::Recovery.new(
      session: kwargs.fetch(:session), turn: nil, items: @recovered, tool_calls: @pending_calls || []
    )
  end

  def record_stream(kwargs, block)
    @calls[:stream] << kwargs
    events = @calls[:stream].size > 1 && @next_stream ? @next_stream : @stream
    Array(events).each { |stream_event| block&.call(stream_event) }
    return kwargs.fetch(:session) if @calls[:stream].size > 1

    @stream_result || kwargs.fetch(:session)
  end

  def record_submit(kwargs, block)
    @calls[:submit_tool_results] << kwargs
    raise @submit_error if @submit_error && @calls[:submit_tool_results].size == 1
    return scripted_submit(kwargs) if @submit_script

    Array(@continuation).each { |stream_event| block&.call(stream_event) }
    kwargs.fetch(:session)
  end

  def scripted_submit(kwargs)
    @submit_script[@calls[:submit_tool_results].size - 1] || kwargs.fetch(:session)
  end

  def with_dispatcher(calls)
    original = RecordingStudioMcp::Dispatcher.method(:call)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**|
      calls << true
      { content: [{ type: "text", text: "ok" }], isError: false }
    end
    yield
  ensure
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  def tool_call(call_id = "call_1")
    RecordingStudioAI::Agents::ToolCall.new(
      call_id: call_id, name: "show", arguments: { "type" => "PressKit", "id" => "missing" },
      provider_turn_id: "turn_1"
    )
  end

  def tool_turn(calls)
    RecordingStudioAI::Agents::Turn.new(
      provider: :openai, provider_session_id: "sess_tools", model: "demo", status: "requires_action",
      run_id: nil, tool_calls: calls
    )
  end

  def timeout_failure
    error = RecordingStudioAI::Contracts::NormalizedError.new(
      category: "timeout", code: "timeout", message: "Provider request timed out.", retryable: true
    )
    RecordingStudioAI::Agents::Failure.new(error)
  end

  def hosted(provider_session_id)
    RecordingStudioAI::Agents::Session.new(
      provider: :openai, provider_session_id: provider_session_id, model: "demo", profile: "medium", status: "in_progress"
    )
  end

  def event(type, text: nil, text_delta: nil)
    RecordingStudioAI::Providers::StreamEvent.new(type: type, text: text, text_delta: text_delta)
  end

  def remember_agent(name)
    @original_agents[name] = RecordingStudioAI::Agents.method(name)
  end

  def restore_agents
    return if @original_agents.nil?

    @original_agents.each do |name, original|
      RecordingStudioAI::Agents.define_singleton_method(name) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end
end
