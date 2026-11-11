# frozen_string_literal: true

require "test_helper"

class McpChatToolsTest < Minitest::Test
  def test_definitions_are_absent_when_mcp_is_not_loaded
    refute RecordingStudioAgents::Mcp::ChatTools.installed?

    assert_nil RecordingStudioAgents::Mcp::ChatTools.definitions(actor: Object.new, root: Object.new)
  end

  def test_chat_and_item_tools_are_treated_as_its_own
    tools = RecordingStudioAgents::Mcp::ChatTools

    assert tools.self_tool?("agent_chats_create")
    assert tools.self_tool?("agent_items_read")
    refute tools.self_tool?("update")
  end
end
