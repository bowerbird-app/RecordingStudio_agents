# frozen_string_literal: true

require "test_helper"

class McpRegistrationTest < Minitest::Test
  def test_register_publishes_chat_endpoints
    with_fake_host do
      RecordingStudioAgents::Mcp.register!
      RecordingStudioAgents::Mcp.register!

      list = RecordingStudioApi.registered_endpoint(:agent_chats_list)
      assert_equal :get, list[:verb]
      assert_equal "agent_chats", list[:path]
      assert_equal RecordingStudioAgents::Mcp::Chats::List, list[:handler]
      assert RecordingStudioApi.registered_endpoint(:agent_chats_create)
      assert_nil RecordingStudioApi.registered_endpoint(:agent_chats_list)[:recordable_type]
      assert_nil RecordingStudioApi.registered_endpoint(:agent_chats_create)[:recordable_type]
      %i[agent_chats_read agent_chats_append agent_items_list agent_items_read].each do |name|
        endpoint = RecordingStudioApi.registered_endpoint(name)
        assert_equal "RecordingStudioAgents::Session", endpoint[:recordable_type]
      end
      assert_equal 6, RecordingStudioApi.endpoints.size
      list_docs = list[:openapi]
      assert_equal ["Agent chats"], list_docs[:tags]
      assert_equal "List chats", list_docs[:summary]
      schema = list_docs.dig(:responses, "200", :content, "application/json", :schema)
      assert_equal "object", schema[:type]
      assert_includes schema[:required], "chats"
      assert_empty RecordingStudioMcp.skills
    end
  end

  def test_each_tool_description_and_input_description_is_present
    with_fake_host do
      RecordingStudioAgents::Mcp.register!

      RecordingStudioAgents::Mcp::ToolCopy::DESCRIPTIONS.each_key do |name|
        endpoint = RecordingStudioApi.registered_endpoint(name)
        document = endpoint.fetch(:openapi)
        description = document.fetch(:description)

        assert description.present?, name
        refute_equal document.fetch(:summary), description
        assert_input_descriptions(name, endpoint.fetch(:input_contract))
        assert_path_descriptions(name, endpoint.fetch(:path), document[:parameters])
      end
    end
  end

  def test_register_does_nothing_until_api_and_mcp_exist
    refute defined?(RecordingStudioApi)
    refute defined?(RecordingStudioMcp)

    RecordingStudioAgents::Mcp.register!

    refute defined?(RecordingStudioApi)
    refute defined?(RecordingStudioMcp)
  end

  private

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

  def with_fake_host
    Object.const_set(:RecordingStudioApi, fake_api)
    Object.const_set(:RecordingStudioMcp, fake_mcp)
    yield
  ensure
    Object.send(:remove_const, :RecordingStudioApi) if defined?(RecordingStudioApi)
    Object.send(:remove_const, :RecordingStudioMcp) if defined?(RecordingStudioMcp)
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
