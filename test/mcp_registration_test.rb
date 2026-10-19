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
      assert_equal 6, RecordingStudioApi.endpoints.size
      assert_includes RecordingStudioMcp.skills.fetch("agent-chats"), "SKILL.md"
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

    def mod.register_endpoint(name, http_verb:, path:, handler:, **)
      endpoints[name] = { verb: http_verb, path: path, handler: handler }
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
