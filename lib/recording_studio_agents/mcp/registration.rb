# frozen_string_literal: true

require_relative "tool_copy"

module RecordingStudioAgents
  module Mcp
    module Registration
      CHAT_LIST = :list_agent_chats
      CHAT_CREATE = :create_agent_chat
      CHAT_READ = :read_agent_chat
      CHAT_APPEND = :append_agent_chat
      ITEM_LIST = :list_agent_items
      ITEM_READ = :read_agent_item
      OWN_TOOLS = [CHAT_LIST, CHAT_CREATE, CHAT_READ, CHAT_APPEND, ITEM_LIST, ITEM_READ].map(&:to_s).freeze
      SESSION_RECORDABLE_TYPE = "RecordingStudioAgents::Session"

      module_function

      def register!
        register_endpoints!
      end

      def own_tool?(name)
        OWN_TOOLS.include?(name.to_s)
      end

      def api_available?
        defined?(::RecordingStudioApi)
      end

      def api
        ::RecordingStudioApi
      end

      def register_endpoints!
        return unless api_available?

        register_chat_endpoints!
        register_item_endpoints!
      end

      def register_chat_endpoints!
        register_endpoint!(CHAT_LIST, [:get, "agent_chats"], Chats::List, "List chats", Contracts.list)
        register_endpoint!(CHAT_CREATE, [:post, "agent_chats"], Chats::Create, "Create a chat", Contracts.create)
        register_endpoint!(CHAT_READ, scoped_route(:get, "agent_chats/:id"), Chats::Read, "Read a chat", Contracts.id)
        register_endpoint!(
          CHAT_APPEND, scoped_route(:post, "agent_chats/:id/messages"), Chats::Append, "Append a message",
          Contracts.append
        )
      end

      def register_item_endpoints!
        register_endpoint!(
          ITEM_LIST, scoped_route(:get, "agent_chats/:id/items"), Items::List, "List chat items", Contracts.items
        )
        register_endpoint!(
          ITEM_READ, scoped_route(:get, "agent_chats/:id/items/:item_id"), Items::Read, "Read a chat item",
          Contracts.item
        )
      end

      def scoped_route(verb, path)
        [verb, path, SESSION_RECORDABLE_TYPE]
      end

      def register_endpoint!(name, route, handler, summary, contract)
        return if registered?(name)

        api.register_endpoint(name, **endpoint_options(name, route, handler, summary, contract))
      end

      def endpoint_options(name, route, handler, summary, contract)
        verb, path, recordable_type = route
        options = {
          http_verb: verb, path: path, handler: handler, input_contract: contract,
          openapi: openapi_for(name, path, summary)
        }
        options[:recordable_type] = recordable_type if recordable_type
        options
      end

      def openapi_for(name, path, summary)
        document = {
          tags: ["Agent chats"],
          summary: summary,
          description: ToolCopy.description(name)
        }.merge(ResponseSchemas.for(name))
        parameters = ToolCopy.path_parameters(path)
        document[:parameters] = parameters if parameters.any?
        document
      end

      def registered?(name)
        return false unless api.respond_to?(:registered_endpoint)

        api.registered_endpoint(name).present?
      end
    end
  end
end
