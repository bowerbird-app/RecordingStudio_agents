# frozen_string_literal: true

require "test_helper"

class McpToolsTest < Minitest::Test
  Grant = Struct.new(:actor) do
    def authorize!(recording:, role:, include_trashed: false)
      [recording, role, include_trashed]
    end
  end
  ToolContext = Struct.new(:access_grant, :root_recording, :params)
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

  def test_list_and_read_authorize_view
    catalog = catalog_double(threads: { data: [{ id: "chat-1" }], has_more: false, after: nil })
    @context.params = { "limit" => 5, id: "chat-1" }
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
    @context.params = { input: "Hello", idempotency_key: "key-1", title: "Hello", id: "chat-9" }
    seen = []

    RecordingStudioAgents::Sessions::Create.stub(:call, lambda { |**kwargs|
      seen << kwargs[:access_grant]
      ServiceResult.new(created)
    }) do
      RecordingStudioAgents::Sessions::Append.stub(:call, lambda { |**kwargs|
        seen << kwargs[:access_grant]
        ServiceResult.new(appended)
      }) do
        assert_equal({ id: "chat-9", title: "Hello" }, RecordingStudioAgents::Mcp::Chats::Create.call(@context))
        assert_equal({ id: "chat-9" }, RecordingStudioAgents::Mcp::Chats::Append.call(@context))
      end
    end
    assert_equal [@context.access_grant, @context.access_grant], seen
  end

  def test_item_list_and_read_use_the_chat_payload
    recording = Recording.new("chat-1", nil)
    item = Object.new
    catalog = catalog_double(found: recording)
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
    forbidden = Object.new
    def forbidden.find!(_id)
      raise RecordingStudioAgents::ChatKit::ProtocolError.new("no", status: 403)
    end
    missing = Object.new
    def missing.find!(_id)
      raise RecordingStudioAgents::ChatKit::ProtocolError.new("gone", status: 404)
    end
    @context.params = { id: "missing" }

    RecordingStudioAgents::ChatKit::Catalog.stub(:new, forbidden) do
      assert_raises(RecordingStudioApi::AuthorizationError) do
        RecordingStudioAgents::Mcp::Chats::Read.call(@context)
      end
    end

    RecordingStudioAgents::ChatKit::Catalog.stub(:new, missing) do
      assert_raises(RecordingStudioApi::NotFoundError) do
        RecordingStudioAgents::Mcp::Chats::Read.call(@context)
      end
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
      assert_includes taken.message, "conflict"
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
    @context.params = { id: "chat-1", item_id: "missing" }
    catalog = catalog_double(found: Recording.new("chat-1", nil))
    RecordingStudioAgents::ChatKit::Catalog.stub(:new, catalog) do
      RecordingStudioAgents::Item.stub(:find_by, nil) do
        assert_raises(RecordingStudioApi::NotFoundError) do
          RecordingStudioAgents::Mcp::Items::Read.call(@context)
        end
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

  def catalog_double(threads: nil, found: nil)
    catalog = Object.new
    catalog.define_singleton_method(:list_threads) { |_params| threads }
    catalog.define_singleton_method(:find!) { |_id| found || Recording.new("chat-1", nil) }
    catalog
  end

  def install_fakes
    @remove_api = !defined?(::RecordingStudioApi)
    @remove_mcp = !defined?(::RecordingStudioMcp)
    @remove_item = !RecordingStudioAgents.const_defined?(:Item, false)
    Object.const_set(:RecordingStudioApi, fake_api) if @remove_api
    Object.const_set(:RecordingStudioMcp, fake_mcp) if @remove_mcp
    RecordingStudioAgents.const_set(:Item, fake_item) if @remove_item
  end

  def remove_fakes
    Object.send(:remove_const, :RecordingStudioApi) if @remove_api
    Object.send(:remove_const, :RecordingStudioMcp) if @remove_mcp
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

  def fake_mcp
    mod = Module.new
    def mod.skills
      @skills ||= {}
    end

    def mod.register_skill(name, path:)
      skills[name] = path
    end
    mod
  end
end
