# frozen_string_literal: true

require_relative "response_schemas/chats"
require_relative "response_schemas/items"

module RecordingStudioAgents
  module Mcp
    module ResponseSchemas
      JSON_CONTENT = "application/json"
      SUCCESS = "200"

      SCHEMAS = {
        agent_chats_list: Chats::LIST,
        agent_chats_create: Chats::CREATE,
        agent_chats_read: Chats::THREAD,
        agent_chats_append: Chats::APPEND,
        agent_items_list: Items::LIST,
        agent_items_read: Items::ITEM
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
