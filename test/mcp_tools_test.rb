# frozen_string_literal: true

require "test_helper"

class McpToolsTest < Minitest::Test
  Grant = Struct.new(:actor) do
    def authorize!(recording:, role:, include_trashed: false)
      [recording, role, include_trashed]
    end
  end
  ToolContext = Struct.new(:access_grant, :root_recording, :params, :recording)
  Recording = Struct.new(:id, :recordable)
  Recordable = Struct.new(:title)
  ServiceResult = Struct.new(:recording) do
    def value!
      recording
    end
  end

  def setup
    install_fakes
    @actor = Object.new
    @root = Recording.new("root-1", nil)
    @context = ToolContext.new(Grant.new(@actor), @root, {})
  end

  def teardown
    remove_fakes
  end

  def test_every_agent_chat_tool_is_not_found_when_agents_are_off
    configuration = RecordingStudioAgents.configuration
    previous = configuration.enabled
    configuration.enabled = false
    @context.params = { id: "chat-1", item_id: "item-1", input: "Hello", idempotency_key: "key-1" }
    @context.recording = Recording.new("chat-1", nil)
    names = RecordingStudioAgents::Mcp::Registration::OWN_TOOLS
    assert_equal names.sort, tool_handlers.keys.map(&:to_s).sort

    RecordingStudioAgents::Sessions::Create.stub(:call, ->(**) { flunk "create ran" }) do
      RecordingStudioAgents::Sessions::Append.stub(:call, ->(**) { flunk "append ran" }) do
        tool_handlers.each_value do |handler|
          error = assert_raises(RecordingStudioApi::NotFoundError) { handler.call(@context) }
          assert_equal "chat was not found", error.message
        end
      end
    end

    configuration.enabled = -> { raise "token=secret-value" }
    assert_raises(RecordingStudioApi::NotFoundError) do
      RecordingStudioAgents::Mcp::Chats::List.call(@context)
    end
  ensure
    configuration.enabled = previous if configuration
  end

  def test_list_and_read_authorize_view
    catalog = catalog_double(threads: { data: [{ id: "chat-1" }], has_more: false, after: nil })
    @context.params = { "limit" => 5, id: "chat-1" }
    @context.recording = Recording.new("chat-1", nil)
    roles = []
    watch_grant(roles)

    RecordingStudioAgents::ChatKit::Catalog.stub(:new, catalog) do
      listed = RecordingStudioAgents::Mcp::Chats::List.call(@context)
      RecordingStudioAgents::ChatKit::Payload.stub(:thread, { id: "chat-1" }) do
        read = RecordingStudioAgents::Mcp::Chats::Read.call(@context)
        assert_equal({ id: "chat-1" }, read)
      end

      ids = listed.fetch(:chats).map { |chat| chat[:id] }
      assert_equal ["chat-1"], ids
      assert_equal false, listed.fetch(:has_more)
    end
    assert_equal %i[view view], roles
  end

  def test_create_and_append_authorize_edit_and_pass_the_grant
    created = Recording.new("chat-9", Recordable.new("Hello"))
    appended = Recording.new("chat-9", nil)
    @context.recording = created
    @context.params = { input: "Hello", idempotency_key: "key-1", title: "Hello", id: "chat-9" }
    seen = []
    recorded = []
    authorized = []
    @context.access_grant.define_singleton_method(:authorize!) do |recording:, role:, include_trashed: false|
      authorized << [recording, role]
      [recording, role, include_trashed]
    end

    RecordingStudioAgents::Sessions::Create.stub(:call, lambda { |**kwargs|
      seen << kwargs[:access_grant]
      recorded << kwargs
      ServiceResult.new(created)
    }) do
      RecordingStudioAgents::Sessions::Append.stub(:call, lambda { |**kwargs|
        seen << kwargs[:access_grant]
        recorded << kwargs
        ServiceResult.new(appended)
      }) do
        assert_equal({ id: "chat-9", title: "Hello" }, RecordingStudioAgents::Mcp::Chats::Create.call(@context))
        assert_equal({ id: "chat-9" }, RecordingStudioAgents::Mcp::Chats::Append.call(@context))
      end
    end
    assert_equal [@context.access_grant, @context.access_grant], seen
    assert_same @actor, recorded.first[:actor]
    assert_same @actor, recorded.first[:event_actor]
    assert_equal({}, recorded.first[:metadata])
    assert_equal [[@root, :edit], [created, :edit]], authorized
    assert_same created, recorded.last[:recording]
  end

  def test_create_records_the_client_and_keeps_the_permission_actor
    client = Object.new
    human = Struct.new(:id).new("user-1")
    grant = Grant.new(@actor)
    grant.define_singleton_method(:api_client) { client }
    grant.define_singleton_method(:authorized_by) { human }
    params = {
      input: "Hello", idempotency_key: "key-1",
      authorized_by_type: "Spoof", authorized_by_id: "spoof-id",
      metadata: { authorized_by_type: "Spoof", note: "stay" }
    }
    context = ToolContext.new(grant, @root, params)
    context.define_singleton_method(:with_authorized_by) do |metadata = {}|
      metadata.merge(authorized_by_type: "User", authorized_by_id: human.id)
    end
    seen = nil

    RecordingStudioAgents::Sessions::Create.stub(:call, lambda { |**kwargs|
      seen = kwargs
      ServiceResult.new(Recording.new("chat-9", Recordable.new("Hello")))
    }) do
      RecordingStudioAgents::Mcp::Chats::Create.call(context)
    end

    assert_same @actor, seen[:actor]
    assert_same client, seen[:event_actor]
    assert_equal({ authorized_by_type: "User", authorized_by_id: "user-1" }, seen[:metadata])
  end

  def test_item_list_and_read_use_the_chat_payload
    recording = Recording.new("chat-1", nil)
    item = Object.new
    catalog = catalog_double(found: recording)
    @context.recording = recording
    @context.params = { "id" => "chat-1", "item_id" => "item-1", "order" => "asc" }
    page = { data: [{ id: "item-1" }], has_more: true, after: "item-1" }

    RecordingStudioAgents::ChatKit::Catalog.stub(:new, catalog) do
      RecordingStudioAgents::ChatKit::Payload.stub(:item_page, page) do
        listed = RecordingStudioAgents::Mcp::Items::List.call(@context)
        ids = listed.fetch(:items).map { |row| row[:id] }
        assert_equal ["item-1"], ids
      end
      RecordingStudioAgents::Item.stub(:find_by, item) do
        RecordingStudioAgents::ChatKit::Payload.stub(:item, { id: "item-1" }) do
          assert_equal({ id: "item-1" }, RecordingStudioAgents::Mcp::Items::Read.call(@context))
        end
      end
    end
  end

  def test_context_maps_protocol_isolation_and_input_errors
    @context.params = { id: "missing" }
    @context.recording = nil
    assert_raises(RecordingStudioApi::NotFoundError) do
      RecordingStudioAgents::Mcp::Chats::Read.call(@context)
    end

    @context.recording = Recording.new("other-chat", nil)
    assert_raises(RecordingStudioApi::NotFoundError) do
      RecordingStudioAgents::Mcp::Chats::Read.call(@context)
    end

    RecordingStudioAgents::Sessions::Create.stub(:call, ->(**) { raise RecordingStudioAgents::IsolationError }) do
      missing = assert_raises(RecordingStudioApi::NotFoundError) do
        RecordingStudioAgents::Mcp::Chats::Create.call(@context)
      end
      assert_equal "chat was not found", missing.message
    end

    clash = lambda { |**|
      raise RecordingStudioAgents::KeyConflictError, "create_idempotency_key is already used in another workspace"
    }
    RecordingStudioAgents::Sessions::Create.stub(:call, clash) do
      taken = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        RecordingStudioAgents::Mcp::Chats::Create.call(@context)
      end
      assert_equal "conflict: create_idempotency_key is already used in another workspace", taken.message
      assert_equal ["conflict"], taken.details
    end

    RecordingStudioAgents::Sessions::Create.stub(:call, ->(**) { raise RecordingStudioAgents::Error, "bad input" }) do
      assert_raises(RecordingStudioApi::InvalidActionInputError) do
        RecordingStudioAgents::Mcp::Chats::Create.call(@context)
      end
    end

    denied = ->(**) { raise RecordingStudioAgents::Sessions::AccessDeniedError, "actor cannot access this recording" }
    RecordingStudioAgents::Sessions::Create.stub(:call, denied) do
      assert_raises(RecordingStudioApi::AuthorizationError) do
        RecordingStudioAgents::Mcp::Chats::Create.call(@context)
      end
    end
  end

  def test_missing_root_and_missing_item_are_rejected
    @context.root_recording = nil
    error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
      RecordingStudioAgents::Mcp::Chats::Create.call(@context)
    end
    assert_equal "root is required", error.message

    @context.root_recording = @root
    @context.recording = Recording.new("chat-1", nil)
    @context.params = { id: "chat-1", item_id: "missing" }
    RecordingStudioAgents::Item.stub(:find_by, nil) do
      assert_raises(RecordingStudioApi::NotFoundError) do
        RecordingStudioAgents::Mcp::Items::Read.call(@context)
      end
    end
  end

  private

  def watch_grant(roles)
    grant = @context.access_grant
    grant.define_singleton_method(:authorize!) do |recording:, role:, include_trashed: false|
      roles << role
      [recording, include_trashed]
    end
  end

  def tool_handlers
    {
      list_agent_chats: RecordingStudioAgents::Mcp::Chats::List,
      create_agent_chat: RecordingStudioAgents::Mcp::Chats::Create,
      read_agent_chat: RecordingStudioAgents::Mcp::Chats::Read,
      append_agent_chat: RecordingStudioAgents::Mcp::Chats::Append,
      list_agent_items: RecordingStudioAgents::Mcp::Items::List,
      read_agent_item: RecordingStudioAgents::Mcp::Items::Read
    }
  end

  def catalog_double(threads: nil, found: nil)
    catalog = Object.new
    catalog.define_singleton_method(:list_threads) { |_params| threads }
    catalog.define_singleton_method(:find!) { |_id| found || Recording.new("chat-1", nil) }
    catalog
  end

  def install_fakes
    @remove_api = !defined?(::RecordingStudioApi)
    @remove_item = !RecordingStudioAgents.const_defined?(:Item, false)
    Object.const_set(:RecordingStudioApi, fake_api) if @remove_api
    RecordingStudioAgents.const_set(:Item, fake_item) if @remove_item
  end

  def remove_fakes
    Object.send(:remove_const, :RecordingStudioApi) if @remove_api
    RecordingStudioAgents.send(:remove_const, :Item) if @remove_item
  end

  def fake_api
    mod = Module.new
    mod.const_set(:AuthorizationError, Class.new(StandardError))
    mod.const_set(:NotFoundError, Class.new(StandardError))
    mod.const_set(:InvalidActionInputError, Class.new(StandardError) do
      attr_reader :details

      def initialize(message = nil, details: [])
        super(message)
        @details = details
      end
    end)
    def mod.endpoints
      @endpoints ||= {}
    end

    def mod.register_endpoint(name, **)
      endpoints[name] = true
    end

    def mod.registered_endpoint(name)
      endpoints[name]
    end
    mod
  end

  def fake_item
    Class.new do
      def self.find_by(**)
        nil
      end
    end
  end
end
