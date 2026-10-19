# frozen_string_literal: true

require "test_helper"

module RecordingStudioApi
  class AuthorizationError < StandardError; end
  class NotFoundError < StandardError; end
  class InvalidActionInputError < StandardError; end

  class << self
    def endpoints
      @endpoints ||= {}
    end

    def register_endpoint(name, **)
      endpoints[name] = true
    end

    def registered_endpoint(name)
      endpoints[name]
    end
  end
end

module RecordingStudioAgents
  class Item
    def self.find_by(**)
      nil
    end
  end
end

module RecordingStudioMcp
  class << self
    def skills
      @skills ||= {}
    end

    def register_skill(name, path:)
      skills[name] = path
    end
  end
end

class McpToolsTest < Minitest::Test
  Grant = Struct.new(:actor)
  ToolContext = Struct.new(:access_grant, :root_recording, :params)
  Recording = Struct.new(:id, :recordable)
  Recordable = Struct.new(:title)
  ServiceResult = Struct.new(:recording) do
    def value!
      recording
    end
  end

  def setup
    @actor = Object.new
    @root = Recording.new("root-1", nil)
    @context = ToolContext.new(Grant.new(@actor), @root, {})
  end

  def test_register_publishes_chat_tools_and_the_skill_once
    RecordingStudioAgents::Mcp.register!
    RecordingStudioAgents::Mcp.register!

    assert RecordingStudioApi.registered_endpoint(:agent_chats_list)
    assert RecordingStudioApi.registered_endpoint(:agent_chats_create)
    assert RecordingStudioApi.registered_endpoint(:agent_chats_read)
    assert RecordingStudioApi.registered_endpoint(:agent_chats_append)
    assert RecordingStudioApi.registered_endpoint(:agent_items_list)
    assert RecordingStudioApi.registered_endpoint(:agent_items_read)
    assert_includes RecordingStudioMcp.skills.fetch("agent-chats"), "SKILL.md"
  end

  def test_list_and_read_return_catalog_chats
    catalog = catalog_double(threads: { data: [{ id: "chat-1" }], has_more: false, after: nil })
    @context.params = { "limit" => 5, id: "chat-1" }

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
  end

  def test_create_and_append_call_the_session_services
    created = Recording.new("chat-9", Recordable.new("Hello"))
    appended = Recording.new("chat-9", nil)
    @context.params = { input: "Hello", idempotency_key: "key-1", title: "Hello", id: "chat-9" }

    RecordingStudioAgents::Sessions::Create.stub(:call, ServiceResult.new(created)) do
      RecordingStudioAgents::Sessions::Append.stub(:call, ServiceResult.new(appended)) do
        assert_equal({ id: "chat-9", title: "Hello" }, RecordingStudioAgents::Mcp::Chats::Create.call(@context))
        assert_equal({ id: "chat-9" }, RecordingStudioAgents::Mcp::Chats::Append.call(@context))
      end
    end
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
      assert_raises(RecordingStudioApi::NotFoundError) do
        RecordingStudioAgents::Mcp::Chats::Create.call(@context)
      end
    end

    RecordingStudioAgents::Sessions::Create.stub(:call, ->(**) { raise RecordingStudioAgents::Error, "bad input" }) do
      assert_raises(RecordingStudioApi::InvalidActionInputError) do
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

  def catalog_double(threads: nil, found: nil)
    catalog = Object.new
    catalog.define_singleton_method(:list_threads) { |_params| threads }
    catalog.define_singleton_method(:find!) { |_id| found || Recording.new("chat-1", nil) }
    catalog
  end
end
