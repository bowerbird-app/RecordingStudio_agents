# frozen_string_literal: true

module RecordingStudioAgents
  module McpCopy
    module Copy
      module ItemText
        ROWS = {
          list_agent_items: [
            "An item is one stored message on a chat.",
            "A user message has type user_message.",
            "An agent reply has type assistant_message.",
            "This lists the items stored for one chat.",
            "Use read_agent_chat for the title and status.",
            "id is the chat recording id from create_agent_chat or list_agent_chats.",
            "A chat you cannot open is not found.",
            "limit is how many items to return.",
            "Omit limit, or send 0 or less, for 20.",
            "A limit above 50 is cut to 50.",
            "order asc is oldest first, by created_at and then id.",
            "order desc, or omitting order, is newest first.",
            "Any other order is newest first.",
            "The result is items, has_more, and after.",
            "A user message has type, id, thread_id, created_at, content, attachments, and inference_options.",
            "content is a list of parts with type input_text and text.",
            "An assistant message has type, id, thread_id, created_at, and content.",
            "Those parts have type output_text, text, and annotations.",
            "thread_id is the chat id.",
            "after is the last item id on this page when has_more is true, and null otherwise.",
            "This tool does not accept after, so you cannot ask for the next page.",
            "A user message is stored by create_agent_chat and append_agent_chat.",
            "An assistant reply is stored when ChatKit reads that turn, so it can be absent just after those calls."
          ].join(" "),
          read_agent_item: [
            "This reads one stored item on one chat.",
            "Use list_agent_items to get the item id.",
            "id is the chat recording id.",
            "item_id is the id of one item from list_agent_items for that chat.",
            "A chat you cannot open is not found.",
            "A missing chat, a chat in another workspace, or an item that is not on this chat is not found.",
            "The result is that item.",
            "Its fields match a user message or an assistant message from list_agent_items."
          ].join(" ")
        }.freeze
      end
    end
  end
end
