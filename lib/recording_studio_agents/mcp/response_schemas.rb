# frozen_string_literal: true

require_relative "response_schemas/chats"
require_relative "response_schemas/items"

module RecordingStudioAgents
  module Mcp
    module ResponseSchemas
      JSON_CONTENT = "application/json"
      SUCCESS = "200"

      SCHEMAS = {
        list_agent_chats: Chats::LIST,
        create_agent_chat: Chats::CREATE,
        read_agent_chat: Chats::THREAD,
        append_agent_chat: Chats::APPEND,
        list_agent_items: Items::LIST,
        read_agent_item: Items::ITEM
      }.freeze

      EXAMPLES = Chats::EXAMPLES.merge(Items::EXAMPLES).freeze

      module_function

      def for(name)
        json_success(SCHEMAS.fetch(name), EXAMPLES.fetch(name))
      end

      def json_success(schema, example)
        {
          responses: {
            SUCCESS => {
              content: {
                JSON_CONTENT => { schema: schema, example: example }
              }
            }
          }
        }
      end
    end
  end
end
