# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    class Catalog
      def initialize(actor, root, page_recording: nil)
        @actor = actor
        @root = root
        @page_recording = page_recording
      end

      def list_threads(params)
        limit = Payload.page_limit(params["limit"])
        chosen, more = collect_threads(limit, visible_cursor(params["after"]))
        thread_page(chosen, more)
      end

      def show_thread(params)
        recording = find!(params["thread_id"])
        Payload.thread(recording, items: Payload.item_page(recording, {}))
      end

      def update_thread(params)
        recording = find!(params["thread_id"])
        renamed = Sessions::Rename.call(
          root_recording: @root, actor: @actor, recording: recording, title: required_title(params["title"])
        ).value!
        Payload.thread(renamed)
      end

      def delete_thread(params)
        recording = find!(params["thread_id"])
        Sessions::Close.call(root_recording: @root, actor: @actor, recording: recording).value!
        {}
      end

      def list_items(params)
        Payload.item_page(find!(params["thread_id"]), params)
      end

      def find!(thread_id)
        recording = chats.find_by(id: thread_id)
        raise ProtocolError.new("chat was not found", status: 404) if recording.nil? || !viewable?(recording)

        recording
      end

      private

      def thread_page(chosen, more)
        {
          data: chosen.map { |recording| Payload.thread(recording) },
          has_more: more,
          after: (chosen.last.id if more)
        }
      end

      def collect_threads(limit, cursor)
        chosen = []
        more = false
        loop do
          need = limit - chosen.size + 1
          rows = thread_batch(cursor, need)
          break if rows.empty?

          cursor, more = take_visible(rows, chosen, limit)
          break if more || rows.size < need
        end
        [chosen, more]
      end

      def take_visible(rows, chosen, limit)
        cursor = nil
        more = false
        rows.each { |recording| cursor, more = keep_row(recording, chosen, limit, cursor, more) }
        [cursor, more]
      end

      def keep_row(recording, chosen, limit, cursor, more)
        return [cursor, more] if more

        cursor = recording
        return [cursor, false] unless viewable?(recording)
        return [cursor, true] if chosen.size >= limit

        chosen << recording
        [cursor, false]
      end

      def visible_cursor(after)
        return if after.blank?

        recording = chats.find_by(id: after)
        recording if recording && viewable?(recording)
      end

      def thread_batch(cursor, count)
        scope = chats.includes(:recordable).order(created_at: :desc, id: :desc)
        scope = older_than(scope, cursor) if cursor
        scope.limit(count).to_a
      end

      def older_than(scope, cursor)
        table = RecordingStudio::Recording.arel_table
        created = table[:created_at]
        same_time = created.eq(cursor.created_at).and(table[:id].lt(cursor.id))
        scope.where(created.lt(cursor.created_at).or(same_time))
      end

      def chats
        scope = RecordingStudio::Recording.for_root(@root.id).where(recordable_type: Session.name)
        scope = scope.where(parent_recording_id: @page_recording.id) if @page_recording
        scope
      end

      def viewable?(recording)
        RecordingStudioAccessible.authorized?(actor: @actor, recording: recording, role: :view)
      end

      def required_title(title)
        text = title.to_s.strip
        raise ProtocolError, "title must be a non-empty string" if text.empty?

        text
      end
    end
  end
end
