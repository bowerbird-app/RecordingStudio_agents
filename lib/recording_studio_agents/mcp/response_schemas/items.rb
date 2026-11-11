# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module ResponseSchemas
      module Items
        USER_MESSAGE = {
          type: "object",
          additionalProperties: false,
          required: %w[type id thread_id created_at content attachments inference_options],
          properties: {
            type: { type: "string", enum: %w[user_message] },
            id: { type: "string" },
            thread_id: { type: "string" },
            created_at: { type: "string" },
            content: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                required: %w[type text],
                properties: {
                  type: { type: "string", enum: %w[input_text] },
                  text: { type: "string" }
                }
              }
            },
            attachments: { type: "array" },
            inference_options: { type: "object", additionalProperties: false }
          }
        }.freeze

        ASSISTANT_MESSAGE = {
          type: "object",
          additionalProperties: false,
          required: %w[type id thread_id created_at content],
          properties: {
            type: { type: "string", enum: %w[assistant_message] },
            id: { type: "string" },
            thread_id: { type: "string" },
            created_at: { type: "string" },
            content: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                required: %w[type text annotations],
                properties: {
                  type: { type: "string", enum: %w[output_text] },
                  text: { type: "string" },
                  annotations: { type: "array" }
                }
              }
            }
          }
        }.freeze

        ITEM = { oneOf: [USER_MESSAGE, ASSISTANT_MESSAGE] }.freeze

        LIST = {
          type: "object",
          additionalProperties: false,
          required: %w[items has_more after],
          properties: {
            items: { type: "array", items: ITEM },
            has_more: { type: "boolean" },
            after: { type: %w[string null] }
          }
        }.freeze

        EXAMPLES = {
          agent_items_list: {
            items: [{
              type: "user_message", id: "item_1", thread_id: "chat_1",
              created_at: "2026-11-11T04:00:01Z",
              content: [{ type: "input_text", text: "Hello" }],
              attachments: [],
              inference_options: {}
            }],
            has_more: false,
            after: nil
          },
          agent_items_read: {
            type: "user_message", id: "item_1", thread_id: "chat_1",
            created_at: "2026-11-11T04:00:01Z",
            content: [{ type: "input_text", text: "Hello" }],
            attachments: [],
            inference_options: {}
          }
        }.freeze
      end
    end
  end
end
