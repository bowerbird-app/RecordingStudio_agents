# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module ResponseSchemas
      module Chats
        THREAD = {
          type: "object",
          additionalProperties: false,
          required: %w[id title created_at status],
          properties: {
            id: { type: "string" },
            title: { type: %w[string null] },
            created_at: { type: "string" },
            status: {
              type: "object",
              additionalProperties: false,
              required: %w[type],
              properties: { type: { type: "string", enum: %w[active closed] } }
            }
          }
        }.freeze

        LIST = {
          type: "object",
          additionalProperties: false,
          required: %w[chats has_more after],
          properties: {
            chats: { type: "array", items: THREAD },
            has_more: { type: "boolean" },
            after: { type: %w[string null] }
          }
        }.freeze

        CREATE = {
          type: "object",
          additionalProperties: false,
          required: %w[id title],
          properties: { id: { type: "string" }, title: { type: %w[string null] } }
        }.freeze

        APPEND = {
          type: "object",
          additionalProperties: false,
          required: %w[id],
          properties: { id: { type: "string" } }
        }.freeze

        EXAMPLES = {
          list_agent_chats: {
            chats: [{
              id: "chat_1", title: "Hello", created_at: "2026-11-11T04:00:00Z",
              status: { type: "active" }
            }],
            has_more: false,
            after: nil
          },
          create_agent_chat: { id: "chat_1", title: "Hello" },
          read_agent_chat: {
            id: "chat_1", title: "Hello", created_at: "2026-11-11T04:00:00Z",
            status: { type: "active" }
          },
          append_agent_chat: { id: "chat_1" }
        }.freeze
      end
    end
  end
end
