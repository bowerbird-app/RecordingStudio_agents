# frozen_string_literal: true

require_relative "mcp/registration"
require_relative "mcp/tool_copy"

module RecordingStudioAgents
  module McpCopy
    OUTPUTS = {
      "list_agent_chats" => "Chats in this workspace, newest first.",
      "create_agent_chat" => "The chat id and title.",
      "read_agent_chat" => "The chat id, title, created time, and status.",
      "append_agent_chat" => "The chat id. This call does not return a new item id.",
      "list_agent_items" => "Stored messages on one chat.",
      "read_agent_item" => "One stored message."
    }.freeze
    TITLES = {
      "list_agent_chats" => "List chats",
      "create_agent_chat" => "Create a chat",
      "read_agent_chat" => "Read a chat",
      "append_agent_chat" => "Append a message",
      "list_agent_items" => "List chat items",
      "read_agent_item" => "Read a chat item"
    }.freeze
    FIELD_TEXT = {
      "list_agent_chats" => { "limit" => Mcp::ToolCopy::LIST_LIMIT, "parent" => Mcp::ToolCopy::LIST_PARENT },
      "read_agent_chat" => { "id" => Mcp::ToolCopy::CHAT_ID },
      "append_agent_chat" => {
        "id" => Mcp::ToolCopy::CHAT_ID,
        "input" => Mcp::ToolCopy::APPEND_INPUT,
        "idempotency_key" => Mcp::ToolCopy::APPEND_KEY
      },
      "list_agent_items" => {
        "id" => Mcp::ToolCopy::CHAT_ID,
        "limit" => Mcp::ToolCopy::ITEM_LIMIT,
        "order" => Mcp::ToolCopy::ORDER
      },
      "read_agent_item" => { "id" => Mcp::ToolCopy::CHAT_ID, "item_id" => Mcp::ToolCopy::ITEM_ID }
    }.freeze

    module_function

    def tool_names
      Mcp::Registration::OWN_TOOLS
    end

    def mcp_available?
      defined?(::RecordingStudioMcp) && ::RecordingStudioMcp.respond_to?(:register_tool)
    end

    def mcp
      ::RecordingStudioMcp
    end

    def register!
      return unless mcp_available?

      tool_names.each { |name| register_named_tool(name) }
    end

    def register_named_tool(name)
      mcp.register_tool(
        name: name,
        endpoint: name.to_sym,
        title: TITLES.fetch(name),
        description: Mcp::ToolCopy.description(name),
        input: input_for(name),
        output: OUTPUTS.fetch(name)
      )
    end

    def input_for(name)
      text = field_text(name)
      text.transform_values { |description| { description: description } }
    end

    def field_text(name)
      return create_fields if name == "create_agent_chat"

      FIELD_TEXT.fetch(name)
    end

    def create_fields
      limit = RecordingStudioAgents.configuration.max_instructions_length
      {
        "input" => Mcp::ToolCopy::CREATE_INPUT,
        "idempotency_key" => Mcp::ToolCopy::CREATE_KEY,
        "title" => Mcp::ToolCopy::TITLE,
        "instructions" => Mcp::ToolCopy.instructions(limit),
        "parent" => Mcp::ToolCopy::PARENT
      }
    end
    private_class_method :register_named_tool, :input_for, :field_text, :create_fields
  end
end
