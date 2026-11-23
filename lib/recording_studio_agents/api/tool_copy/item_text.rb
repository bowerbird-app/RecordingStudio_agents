# frozen_string_literal: true

module RecordingStudioAgents
  module Api
    module ToolCopy
      module ItemText
        ROWS = {
          list_agent_items: [
            "Lists the stored messages on one chat.",
            "A user message has type user_message.",
            "An assistant reply has type assistant_message.",
            "id is the chat recording id.",
            "A chat the caller cannot open is not found.",
            "limit is how many items to return.",
            "Omit limit, or send 0 or less, for 20.",
            "A limit above 50 is cut to 50.",
            "order asc is oldest first, by created_at and then id.",
            "order desc, or omitting order, is newest first.",
            "Any other order is newest first.",
            "The response is items, has_more, and after.",
            "A user message has type, id, thread_id, created_at, content, attachments, and inference_options.",
            "content is a list of parts with type input_text and text.",
            "An assistant message has type, id, thread_id, created_at, and content.",
            "Those parts have type output_text, text, and annotations.",
            "thread_id is the chat id.",
            "after is the last item id on this page when has_more is true, and null otherwise.",
            "The request does not accept after, so it cannot ask for the next page.",
            "A user message is stored by create and by append.",
            "An assistant reply is stored when the chat client reads that turn, " \
            "so it can be absent just after those calls."
          ].join(" "),
          read_agent_item: [
            "Returns one stored item on one chat.",
            "id is the chat recording id.",
            "item_id is the id of one item on that chat, from the items list.",
            "A chat the caller cannot open is not found.",
            "A missing chat, a chat in another workspace, or an item that is not on this chat is not found.",
            "The response is that item.",
            "Its fields match a user message or an assistant message from the items list."
          ].join(" ")
        }.freeze
      end
    end
  end
end
