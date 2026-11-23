# frozen_string_literal: true

module RecordingStudioAgents
  module Api
    module ToolCopy
      module ChatText
        ROWS = {
          list_agent_chats: [
            "Lists chats in the workspace for this request, newest created_at first.",
            "Query parent to return only the chats stored under that recording.",
            "Omit parent to list every chat in the workspace.",
            "parent is the recording id of a record in this workspace that can hold a chat.",
            "The record must be in this workspace and not trashed.",
            "A missing, trashed, or cross-workspace parent is not found.",
            "A parent the caller cannot open is not authorized.",
            "A parent whose type cannot hold a chat is rejected.",
            "limit is how many chats to return.",
            "Omit limit, or send 0 or less, for 20.",
            "A limit above 50 is cut to 50.",
            "The response has chats, has_more, and after.",
            "Each chat has id, title, created_at, and status.type of active or closed.",
            "title is null when the chat was opened without one.",
            "after is the last chat id on this page when has_more is true, and null otherwise.",
            "The request does not accept after, so it cannot ask for the next page."
          ].join(" "),
          create_agent_chat: [
            "Opens a chat and stores the first user message.",
            "The body needs a non-empty input and an idempotency_key.",
            "A caller that cannot change the workspace is not authorized.",
            "input is the first user message, and it must be a non-empty string.",
            "idempotency_key is a string the caller chooses.",
            "The same key in this workspace returns the existing chat and does not change it.",
            "A new parent, title, input, or instructions is not saved.",
            "The request still requires a non-empty input, and a parent must still be a record the caller can change.",
            "The same key in another workspace opens a second chat.",
            "If an older global unique index is still installed, that second chat fails with a conflict.",
            "title is optional.",
            "Omit title and the stored title is null.",
            "parent is optional.",
            "It is the recording id of a record in this workspace that can hold a chat.",
            "Omit parent and the chat belongs to the workspace.",
            "A missing, trashed, or cross-workspace parent is not found.",
            "A parent the caller can open but not change is not authorized.",
            "A parent whose type cannot hold a chat is rejected.",
            "instructions is optional extra text.",
            "The default cap is 4000 characters, and a blank value uses the host default.",
            "A real override is rejected unless the host allows an instructions override.",
            "When an override is allowed, the text is appended after the host default.",
            "A fixed safety line always comes first and is not counted in the cap.",
            "The response is id and title.",
            "This call does not return the assistant reply.",
            "The user message is stored as an item.",
            "The reply is stored when the chat client reads that turn, " \
            "so the items list can show only the user message."
          ].join(" "),
          read_agent_chat: [
            "Returns one chat in the workspace for this request.",
            "id is the chat recording id, from the list or create response.",
            "A missing chat, or a chat in another workspace, is not found.",
            "A chat the caller cannot open is not found.",
            "The response is id, title, created_at, and status.type of active or closed.",
            "title is null when the chat was opened without one.",
            "The response does not include the messages or the parent id."
          ].join(" "),
          append_agent_chat: [
            "Adds one user message to an existing chat.",
            "The body needs a non-empty input and an idempotency_key.",
            "A caller that cannot change the chat is not authorized.",
            "id is the chat recording id.",
            "input is the message, and it must be a non-empty string.",
            "idempotency_key is a string the caller chooses.",
            "The same key on this chat returns the chat again and does not store a second message.",
            "A different input with that key is not saved.",
            "The input must still be a non-empty string.",
            "The same key on a different chat in this workspace is rejected.",
            "The response is id, which is the chat id, not a new item id.",
            "This call does not return the assistant reply.",
            "The user message is stored as an item.",
            "The reply is stored when the chat client reads that turn, so it can be missing until then."
          ].join(" ")
        }.freeze
      end
    end
  end
end
