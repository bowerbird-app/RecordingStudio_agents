# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    class AssistantTurn
      attr_reader :item_id, :text, :created_at

      def initialize(thread_id)
        @thread_id = thread_id
        @item_id = SecureRandom.uuid
        @text = +""
        @created_at = Time.current
        @added = false
        @finished = false
      end

      def apply(event)
        return [] if @finished

        case event.type.to_s
        when "text_delta" then delta(event.text_delta.to_s)
        when "message_completed" then complete(event.text.to_s)
        when "turn_completed" then finish
        when "failed" then [failure("The response failed.", true)]
        when "cancelled" then [failure("The response was cancelled.", false)]
        else []
        end
      end

      def savable?
        @finished && @text.present?
      end

      private

      def delta(piece)
        return [] if piece.empty?

        events = []
        events << added_event unless @added
        @added = true
        @text << piece
        events << delta_event(piece)
        events
      end

      def complete(full)
        @text = full if full.present?
        finish
      end

      def finish
        return [] if @finished || @text.blank?

        @finished = true
        [done_event]
      end

      def added_event
        { type: "thread.item.added", item: message("") }
      end

      def done_event
        { type: "thread.item.done", item: message(@text) }
      end

      def delta_event(piece)
        {
          type: "thread.item.updated", item_id: @item_id,
          update: { type: "assistant_message.content_part.text_delta", content_index: 0, delta: piece }
        }
      end

      def message(text)
        Payload.assistant_message(id: @item_id, thread_id: @thread_id, text: text, created_at: @created_at)
      end

      def failure(message, retryable)
        @finished = true
        { type: "error", code: "custom", message: message, allow_retry: retryable }
      end
    end
  end
end
