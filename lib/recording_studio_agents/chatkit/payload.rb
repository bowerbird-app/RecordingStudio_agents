# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    module Payload
      module_function

      def thread(recording, items: nil)
        body = {
          id: recording.id, title: recording.recordable.title, created_at: stamp(recording.created_at),
          status: { type: recording.recordable.status == "closed" ? "closed" : "active" }
        }
        body[:items] = items if items
        body
      end

      def user_message(item, thread_id)
        {
          type: "user_message", id: item.id, thread_id: thread_id, created_at: stamp(item.created_at),
          content: [{ type: "input_text", text: item.text }], attachments: [], inference_options: {}
        }
      end

      def assistant_message(id:, thread_id:, text:, created_at:)
        {
          type: "assistant_message", id: id, thread_id: thread_id, created_at: stamp(created_at),
          content: [{ type: "output_text", text: text, annotations: [] }]
        }
      end

      def item(record, thread_id)
        return user_message(record, thread_id) if record.role == "user"

        assistant_message(id: record.id, thread_id: thread_id, text: record.text, created_at: record.created_at)
      end

      def item_page(recording, params)
        limit = page_limit(params["limit"])
        rows = ordered_items(recording, params).limit(limit + 1).to_a
        visible = rows.first(limit)
        {
          data: visible.map { |record| item(record, recording.id) },
          has_more: rows.size > limit,
          after: rows.size > limit ? visible.last&.id : nil
        }
      end

      def user_text(input)
        parts = input.is_a?(Hash) ? Array(input["content"]) : []
        text = parts.filter_map { |part| part_text(part) }.join("\n").strip
        raise ProtocolError, "input must be a non-empty string" if text.empty?

        text
      end

      def stamp(time)
        time&.iso8601
      end

      def page_limit(value)
        number = value.to_i
        return 20 if number <= 0

        [number, 50].min
      end

      def ordered_items(recording, params)
        direction = params["order"] == "asc" ? :asc : :desc
        scope = Item.where(recording_id: recording.id).order(created_at: direction, id: direction)
        cursor = Item.find_by(id: params["after"], recording_id: recording.id)
        return scope if cursor.nil?

        after_cursor(scope, cursor, direction)
      end

      def after_cursor(scope, cursor, direction)
        scope.where(cursor_predicate(cursor, direction))
      end

      def cursor_predicate(cursor, direction)
        created = Item.arel_table[:created_at]
        same_time = created.eq(cursor.created_at).and(compare(Item.arel_table[:id], cursor.id, direction))
        compare(created, cursor.created_at, direction).or(same_time)
      end

      def compare(column, value, direction)
        direction == :asc ? column.gt(value) : column.lt(value)
      end

      def part_text(part)
        return unless part.is_a?(Hash) && part["type"] == "input_text"

        part["text"].to_s
      end
    end
  end
end
