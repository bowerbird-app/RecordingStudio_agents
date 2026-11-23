# frozen_string_literal: true

require_relative "tool_copy/chat_text"
require_relative "tool_copy/item_text"

module RecordingStudioAgents
  module Api
    module ToolCopy
      CHAT_ID = "Recording id of the chat, from the list or create response."
      ITEM_ID = "Id of one item on this chat, from the items list."
      CREATE_INPUT = "First user message. Must be a non-empty string. " \
                     "A repeated idempotency_key does not replace the message already stored."
      APPEND_INPUT = "Next user message on this chat. Must be a non-empty string."
      CREATE_KEY = "String the caller chooses. Unique inside this workspace. " \
                   "The same key returns the existing chat and does not change its parent, title, " \
                   "stored message, or instructions. " \
                   "The request still requires a non-empty input, " \
                   "and a parent must still be a record the caller can change. " \
                   "The same key in another workspace opens a second chat, unless an older global unique index " \
                   "rejects it as a conflict."
      APPEND_KEY = "String the caller chooses for this message. Unique inside this workspace. " \
                   "The same key on this chat returns the chat and does not store a second message, " \
                   "even if input is different. The input must still be a non-empty string. " \
                   "The same key on another chat in this workspace is rejected. " \
                   "The same key in another workspace is a new message, unless an older global unique index " \
                   "rejects it as a conflict."
      TITLE = "Optional chat title. Omit it and the stored title is null."
      PARENT = "Optional recording id of a record in this workspace that can hold a chat. " \
               "Omit it and the chat belongs to the workspace. The caller must be able to change that record. " \
               "It must not be trashed. A missing, trashed, or cross-workspace id is not found. " \
               "A type that cannot hold a chat is rejected."
      LIST_PARENT = "Optional recording id of a record in this workspace that can hold a chat. " \
                    "Omit it to list the whole workspace. The caller must be able to open that record. " \
                    "It must not be trashed. A missing, trashed, or cross-workspace id is not found. " \
                    "A type that cannot hold a chat is rejected."
      LIST_LIMIT = "How many chats to return. Omit it, or send 0 or less, for 20. " \
                   "A value above 50 is cut to 50. There is no page cursor."
      ITEM_LIMIT = "How many items to return. Omit it, or send 0 or less, for 20. " \
                   "A value above 50 is cut to 50. There is no page cursor."
      ORDER = "asc is oldest first, by created_at and then id. " \
              "desc, or omitting this, is newest first. Any other value is newest first."

      PATH = { id: CHAT_ID, item_id: ITEM_ID }.freeze
      SUMMARIES = {
        list_agent_chats: "List chats",
        create_agent_chat: "Create a chat",
        read_agent_chat: "Read a chat",
        append_agent_chat: "Append a message",
        list_agent_items: "List chat items",
        read_agent_item: "Read a chat item"
      }.freeze
      DESCRIPTIONS = ChatText::ROWS.merge(ItemText::ROWS).freeze

      module_function

      def description(name)
        DESCRIPTIONS.fetch(name.to_sym)
      end

      def summary(name)
        SUMMARIES.fetch(name.to_sym)
      end

      def instructions(limit)
        "Optional extra instructions for this chat, at most #{limit} characters. " \
          "Blank uses the host default. " \
          "A real override is rejected unless the host allows an instructions override. " \
          "When an override is allowed, the text is appended after the host default. " \
          "A fixed safety line always comes first and is not counted in the cap. " \
          "The chat frame does not send this field."
      end

      def path_parameters(path)
        path.to_s.scan(/:([a-z][a-z0-9_]*)/).flatten.map do |token|
          {
            name: token,
            in: "path",
            required: true,
            description: PATH.fetch(token.to_sym)
          }
        end
      end
    end
  end
end
