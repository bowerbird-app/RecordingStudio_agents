# frozen_string_literal: true

require "test_helper"
require_relative "mcp_json_schema"

class McpResponseSchemasTest < Minitest::Test
  Grant = Struct.new(:actor) do
    def authorize!(recording:, role:, include_trashed: false)
      [recording, role, include_trashed]
    end
  end
  ToolContext = Struct.new(:access_grant, :root_recording, :params)
  Recording = Struct.new(:id, :recordable, :created_at)
  Recordable = Struct.new(:title, :status)
  ItemRow = Struct.new(:id, :role, :text, :created_at)
  ServiceResult = Struct.new(:recording) do
    def value!
      recording
    end
  end

  def setup
    install_fakes
    @stamp = Time.utc(2026, 11, 11, 4, 0, 0)
    @recording = Recording.new("chat_1", Recordable.new("Hello", "active"), @stamp)
    @context = ToolContext.new(Grant.new(Object.new), Recording.new("root-1", nil, nil), { id: "chat_1" })
  end

  def teardown
    remove_fakes
  end

  def test_each_registered_schema_matches_a_handler_response
    RecordingStudioAgents::Mcp.register!
    schemas = registered_schemas
    responses = handler_responses

    names = RecordingStudioAgents::Mcp::ResponseSchemas::SCHEMAS.keys
    assert_equal names.sort, RecordingStudioApi.endpoints.keys.sort

    names.each do |name|
      schema = schemas.fetch(name)
      error = McpJsonSchema.error(schema, responses.fetch(name))
      assert_nil error, "#{name}: #{error}\n#{responses.fetch(name).inspect}"
      example_error = McpJsonSchema.error(schema, example_for(name))
      assert_nil example_error, "#{name} example: #{example_error}"
    end
  end

  private

  def handler_responses
    thread = RecordingStudioAgents::ChatKit::Payload.thread(@recording)
    user = user_item
    assistant = RecordingStudioAgents::ChatKit::Payload.item(
      ItemRow.new("item_2", "assistant", "Hi", @stamp + 2), "chat_1"
    )
    catalog = catalog_double(threads: { data: [thread], has_more: false, after: nil }, found: @recording)
    created = Recording.new("chat_1", Recordable.new("Hello", "active"), @stamp)
    page = { data: [user, assistant], has_more: false, after: nil }

    RecordingStudioAgents::ChatKit::Catalog.stub(:new, catalog) do
      listed_and_read(thread).merge(written(created)).merge(item_payloads(page, user))
    end
  end

  def listed_and_read(thread)
    {
      agent_chats_list: RecordingStudioAgents::Mcp::Chats::List.call(@context),
      agent_chats_read: RecordingStudioAgents::ChatKit::Payload.stub(:thread, thread) do
        RecordingStudioAgents::Mcp::Chats::Read.call(@context)
      end
    }
  end

  def written(created)
    {
      agent_chats_create: RecordingStudioAgents::Sessions::Create.stub(:call, ServiceResult.new(created)) do
        RecordingStudioAgents::Mcp::Chats::Create.call(@context)
      end,
      agent_chats_append: RecordingStudioAgents::Sessions::Append.stub(:call, ServiceResult.new(created)) do
        RecordingStudioAgents::Mcp::Chats::Append.call(@context)
      end
    }
  end

  def item_payloads(page, user)
    {
      agent_items_list: RecordingStudioAgents::ChatKit::Payload.stub(:item_page, page) do
        RecordingStudioAgents::Mcp::Items::List.call(@context)
      end,
      agent_items_read: RecordingStudioAgents::Item.stub(:find_by, user_row) do
        RecordingStudioAgents::ChatKit::Payload.stub(:item, user) do
          RecordingStudioAgents::Mcp::Items::Read.call(@context)
        end
      end
    }
  end

  def user_item
    RecordingStudioAgents::ChatKit::Payload.item(user_row, "chat_1")
  end

  def user_row
    ItemRow.new("item_1", "user", "Hello", @stamp + 1)
  end

  def registered_schemas
    RecordingStudioApi.endpoints.each_with_object({}) do |(name, endpoint), acc|
      acc[name] = json_content(endpoint).fetch(:schema)
    end
  end

  def example_for(name)
    json_content(RecordingStudioApi.endpoints.fetch(name)).fetch(:example)
  end

  def json_content(endpoint)
    endpoint.fetch(:openapi).dig(:responses, "200", :content, "application/json")
  end

  def catalog_double(threads:, found:)
    catalog = Object.new
    catalog.define_singleton_method(:list_threads) { |_params| threads }
    catalog.define_singleton_method(:find!) { |_id| found }
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

  def fake_item
    Class.new do
      def self.find_by(**)
        nil
      end
    end
  end

  def fake_api
    mod = Module.new
    mod.const_set(:AuthorizationError, Class.new(StandardError))
    mod.const_set(:NotFoundError, Class.new(StandardError))
    mod.const_set(:InvalidActionInputError, Class.new(StandardError))
    def mod.endpoints
      @endpoints ||= {}
    end

    def mod.register_endpoint(name, **kwargs)
      endpoints[name] = kwargs.merge(verb: kwargs[:http_verb])
    end

    def mod.registered_endpoint(name)
      endpoints[name]
    end
    mod
  end
end
