# frozen_string_literal: true

require "test_helper"

class McpRegistrationTest < Minitest::Test
  def test_register_publishes_chat_endpoints
    fake = RecordingApi.new

    with_api(fake) do
      RecordingStudioAgents::Mcp.register!
      RecordingStudioAgents::Mcp.register!
    end

    list = fake.endpoints.fetch(:list_agent_chats)
    assert_equal :get, list[:verb]
    assert_equal "agent_chats", list[:path]
    assert_equal RecordingStudioAgents::Mcp::Chats::List, list[:handler]
    assert fake.endpoints.key?(:create_agent_chat)
    assert_nil fake.endpoints.fetch(:list_agent_chats)[:recordable_type]
    assert_nil fake.endpoints.fetch(:create_agent_chat)[:recordable_type]
    %i[read_agent_chat append_agent_chat list_agent_items read_agent_item].each do |name|
      endpoint = fake.endpoints.fetch(name)
      assert_equal "RecordingStudioAgents::Session", endpoint[:recordable_type]
    end
    assert_equal 6, fake.endpoints.size
    list_docs = list[:openapi]
    assert_equal ["Agent chats"], list_docs[:tags]
    assert_equal "List chats", list_docs[:summary]
    schema = list_docs.dig(:responses, "200", :content, "application/json", :schema)
    assert_equal "object", schema[:type]
    assert_includes schema[:required], "chats"
  end

  def test_each_tool_description_and_input_description_is_present
    fake = RecordingApi.new

    with_api(fake) { RecordingStudioAgents::Mcp.register! }

    api = RecordingStudioAgents::Api::ToolCopy
    mcp = RecordingStudioAgents::McpCopy::Copy

    api::DESCRIPTIONS.each_key do |name|
      endpoint = fake.endpoints.fetch(name)
      document = endpoint.fetch(:openapi)
      description = document.fetch(:description)

      assert_equal api.summary(name), document.fetch(:summary)
      assert_equal api.description(name), description
      assert description.present?, name
      refute_equal document.fetch(:summary), description
      refute_equal mcp.description(name), description
      refute_includes description, "this tool"
      %w[view edit admin permission].each { |word| refute_includes description.downcase, word, name }
      assert mcp.description(name).present?
      assert_input_descriptions(name, endpoint.fetch(:input_contract))
      assert_path_descriptions(name, endpoint.fetch(:path), document[:parameters])
    end

    listed = fields(fake.endpoints.fetch(:list_agent_chats).fetch(:input_contract))
    assert_equal api::LIST_LIMIT, listed.dig(:limit, :description)
    refute_equal mcp::LIST_LIMIT, listed.dig(:limit, :description)
    chat_id = fields(fake.endpoints.fetch(:read_agent_chat).fetch(:input_contract)).dig(:id, :description)
    assert_equal api::CHAT_ID, chat_id
    refute_equal mcp::CHAT_ID, chat_id
  end

  def test_register_does_nothing_until_api_and_mcp_exist
    refute defined?(RecordingStudioApi)
    refute defined?(RecordingStudioMcp)

    RecordingStudioAgents::Mcp.register!
    RecordingStudioAgents::McpCopy.register!

    refute defined?(RecordingStudioApi)
    refute defined?(RecordingStudioMcp)
  end

  private

  def with_api(fake, &)
    registration = RecordingStudioAgents::Mcp::Registration
    registration.stub(:api_available?, true) do
      registration.stub(:api, fake, &)
    end
  end

  def assert_input_descriptions(name, contract)
    fields(contract).each do |field, rules|
      text = rules.fetch(:description).to_s

      assert text.present?, "#{name}.#{field}"
      refute_match(/\APath parameter/, text, "#{name}.#{field}")
    end
  end

  def assert_path_descriptions(name, path, parameters)
    tokens = path.to_s.scan(/:([a-z][a-z0-9_]*)/).flatten
    listed = Array(parameters).to_h { |parameter| [parameter.fetch(:name), parameter.fetch(:description).to_s] }

    assert_equal tokens, listed.keys
    listed.each_value do |text|
      assert text.present?, name
      refute_match(/\APath parameter/, text, name)
    end
  end

  def fields(contract)
    body = contract.is_a?(Hash) ? contract : contract.as_json
    body.deep_symbolize_keys.fetch(:fields)
  end

  class RecordingApi
    def initialize
      @endpoints = {}
    end

    attr_reader :endpoints

    def register_endpoint(name, **kwargs)
      endpoints[name] = kwargs.merge(verb: kwargs[:http_verb])
    end

    def registered_endpoint(name)
      endpoints[name]
    end
  end
end
