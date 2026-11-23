# frozen_string_literal: true

require_relative "mcp_copy/copy"
require_relative "mcp/registration"

module RecordingStudioAgents
  module McpCopy
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
        title: Copy::TITLES.fetch(name),
        description: Copy.description(name),
        input: input_for(name),
        output: Copy::OUTPUTS.fetch(name)
      )
    end

    def input_for(name)
      text = field_text(name)
      text.transform_values { |description| { description: description } }
    end

    def field_text(name)
      return create_fields if name == "create_agent_chat"

      FIELDS.fetch(name)
    end

    def create_fields
      limit = RecordingStudioAgents.configuration.max_instructions_length
      {
        "input" => Copy::CREATE_INPUT,
        "idempotency_key" => Copy::CREATE_KEY,
        "title" => Copy::TITLE,
        "instructions" => Copy.instructions(limit),
        "parent" => Copy::PARENT
      }
    end

    FIELDS = {
      "list_agent_chats" => { "limit" => Copy::LIST_LIMIT, "parent" => Copy::LIST_PARENT },
      "read_agent_chat" => { "id" => Copy::CHAT_ID },
      "append_agent_chat" => {
        "id" => Copy::CHAT_ID,
        "input" => Copy::APPEND_INPUT,
        "idempotency_key" => Copy::APPEND_KEY
      },
      "list_agent_items" => {
        "id" => Copy::CHAT_ID,
        "limit" => Copy::ITEM_LIMIT,
        "order" => Copy::ORDER
      },
      "read_agent_item" => { "id" => Copy::CHAT_ID, "item_id" => Copy::ITEM_ID }
    }.freeze
    private_class_method :register_named_tool, :input_for, :field_text, :create_fields
  end
end
