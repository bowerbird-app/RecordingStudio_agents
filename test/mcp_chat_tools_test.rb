# frozen_string_literal: true

require "test_helper"

class McpChatToolsTest < Minitest::Test
  def test_definitions_are_absent_when_mcp_is_not_loaded
    refute RecordingStudioAgents::Mcp::ChatTools.installed?

    assert_nil RecordingStudioAgents::Mcp::ChatTools.definitions(actor: Object.new, root: Object.new)
  end

  def test_an_empty_allow_list_blocks_every_tool_name
    configuration = RecordingStudioAgents.configuration
    previous = configuration.mcp_tool_allow
    configuration.mcp_tool_allow = []

    refute RecordingStudioAgents::Mcp::ChatTools.named_tool?("show")
  ensure
    configuration.mcp_tool_allow = previous if configuration
  end

  def test_an_unknown_mode_falls_back_to_write
    configuration = RecordingStudioAgents.configuration
    previous = configuration.mcp_tools
    configuration.instance_variable_set(:@mcp_tools, :sideways)

    assert_equal :write, RecordingStudioAgents::Mcp::ChatTools.mode
  ensure
    configuration.mcp_tools = previous if configuration && previous
  end

  def test_chat_and_item_tools_are_treated_as_its_own
    tools = RecordingStudioAgents::Mcp::ChatTools

    assert tools.self_tool?("agent_chats_create")
    assert tools.self_tool?("agent_items_read")
    refute tools.self_tool?("agent_chats_extra")
    refute tools.self_tool?("update")
  end
end
