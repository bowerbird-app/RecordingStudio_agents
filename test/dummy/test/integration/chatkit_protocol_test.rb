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
    @configuration = RecordingStudioAgents.configuration
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
    end
    restore_agents
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

  def create_body(text, root_id: nil)
    { type: "threads.create", params: create_params(text), metadata: { root_recording_id: root_id } }.to_json
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
    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(recording).record(
        RecordingStudio::Access, actor: actor, parent_recording: recording
      ) do |access|
        access.actor = actor
        access.role = "edit"
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
      stream: ->(**kwargs, &block) { helper.send(:record_stream, kwargs, block) }
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
    RecordingStudioAI::Agents::Recovery.new(session: kwargs.fetch(:session), turn: nil, items: @recovered)
  end

  def record_stream(kwargs, block)
    @calls[:stream] << kwargs
    @stream.each { |stream_event| block&.call(stream_event) }
    kwargs.fetch(:session)
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
