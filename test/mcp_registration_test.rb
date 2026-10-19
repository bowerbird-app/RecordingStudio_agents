# frozen_string_literal: true

require "test_helper"

class McpRegistrationTest < Minitest::Test
  def test_register_waits_for_the_host_to_load_api_and_mcp
    registration = File.read(File.expand_path("../lib/recording_studio_agents/mcp/registration.rb", __dir__))

    assert_includes registration, "return unless defined?(RecordingStudioApi)"
    assert_includes registration, "return unless defined?(RecordingStudioMcp)"
  end

  def test_skill_document_names_the_chat_tools
    text = File.read(File.expand_path("../lib/recording_studio_agents/mcp/SKILL.md", __dir__))

    assert_includes text, "name: agent-chats"
    assert_includes text, "agent_chats_list"
    assert_includes text, "agent_chats_create"
    assert_includes text, "agent_items_read"
  end
end
