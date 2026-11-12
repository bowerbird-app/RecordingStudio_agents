# frozen_string_literal: true

require "test_helper"

class McpRegistrationTest < Minitest::Test
  def test_register_publishes_chat_endpoints_and_the_skill
    with_fake_host do
      RecordingStudioAgents::Mcp.register!
      RecordingStudioAgents::Mcp.register!

      list = RecordingStudioApi.registered_endpoint(:agent_chats_list)
      assert_equal :get, list[:verb]
      assert_equal "agent_chats", list[:path]
      assert_equal RecordingStudioAgents::Mcp::Chats::List, list[:handler]
      assert RecordingStudioApi.registered_endpoint(:agent_chats_create)
      assert RecordingStudioApi.registered_endpoint(:agent_chats_read)
      assert RecordingStudioApi.registered_endpoint(:agent_chats_append)
      assert RecordingStudioApi.registered_endpoint(:agent_items_list)
      assert RecordingStudioApi.registered_endpoint(:agent_items_read)
      assert_equal 8, RecordingStudioApi.endpoints.size
      list_docs = list[:openapi]
      assert_equal ["Agent chats"], list_docs[:tags]
      assert_equal "List chats", list_docs[:summary]
      schema = list_docs.dig(:responses, "200", :content, "application/json", :schema)
      assert_equal "object", schema[:type]
      assert_includes schema[:required], "chats"
      assert_includes RecordingStudioMcp.skills.fetch("agent-chats"), "SKILL.md"
    end
  end

  def test_register_publishes_close_and_rename
    with_fake_host do
      RecordingStudioAgents::Mcp.register!

      closed = RecordingStudioApi.registered_endpoint(:agent_chats_close)
      renamed = RecordingStudioApi.registered_endpoint(:agent_chats_rename)
      assert_equal :delete, closed[:verb]
      assert_equal "agent_chats/:id", closed[:path]
      assert_equal "Agent Chat - Close", closed[:openapi][:summary]
      assert_equal :patch, renamed[:verb]
      assert_equal "Agent Chat - Rename", renamed[:openapi][:summary]
    end
  end

  def test_register_does_nothing_until_api_and_mcp_exist
    refute defined?(RecordingStudioApi)
    refute defined?(RecordingStudioMcp)

    RecordingStudioAgents::Mcp.register!

    refute defined?(RecordingStudioApi)
    refute defined?(RecordingStudioMcp)
  end

  def test_skill_document_names_the_chat_tools
    text = File.read(File.expand_path("../lib/recording_studio_agents/mcp/SKILL.md", __dir__))

    assert_includes text, "name: agent-chats"
    assert_includes text, "agent_chats_list"
    assert_includes text, "agent_chats_create"
    assert_includes text, "agent_chats_close"
    assert_includes text, "agent_chats_rename"
    assert_includes text, "agent_items_read"
  end

  private

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
