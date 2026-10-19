# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module Registration
      CHAT_LIST = :agent_chats_list
      CHAT_CREATE = :agent_chats_create
      CHAT_READ = :agent_chats_read
      CHAT_APPEND = :agent_chats_append
      ITEM_LIST = :agent_items_list
      ITEM_READ = :agent_items_read
      SKILL_NAME = "agent-chats"

      module_function

      def register!
        register_endpoints!
        register_skill!
      end

      def register_endpoints!
        return unless defined?(RecordingStudioApi)

        register_chat_endpoints!
        register_item_endpoints!
      end

      def register_skill!
        return unless defined?(RecordingStudioMcp)

        RecordingStudioMcp.register_skill(SKILL_NAME, path: skill_path)
      end

      def register_chat_endpoints!
        register_endpoint!(CHAT_LIST, [:get, "agent_chats"], Chats::List, "List chats", Contracts.list)
        register_endpoint!(CHAT_CREATE, [:post, "agent_chats"], Chats::Create, "Create a chat", Contracts.create)
        register_endpoint!(CHAT_READ, [:get, "agent_chats/:id"], Chats::Read, "Read a chat", Contracts.id)
        register_endpoint!(
          CHAT_APPEND, [:post, "agent_chats/:id/messages"], Chats::Append, "Append a message", Contracts.append
        )
      end

      def register_item_endpoints!
        register_endpoint!(ITEM_LIST, [:get, "agent_chats/:id/items"], Items::List, "List chat items", Contracts.items)
        register_endpoint!(
          ITEM_READ, [:get, "agent_chats/:id/items/:item_id"], Items::Read, "Read a chat item", Contracts.item
        )
      end

      def register_endpoint!(name, route, handler, summary, contract)
        return if registered?(name)

        verb, path = route
        RecordingStudioApi.register_endpoint(
          name,
          http_verb: verb,
          path: path,
          handler: handler,
          input_contract: contract,
          openapi: { tags: ["Agent chats"], summary: summary, description: summary }
        )
      end

      def registered?(name)
        return false unless RecordingStudioApi.respond_to?(:registered_endpoint)

        RecordingStudioApi.registered_endpoint(name).present?
      end

      def skill_path
        File.expand_path("SKILL.md", __dir__)
      end
    end
  end
end
