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
        page(visible_chats, params) { |recording| Payload.thread(recording) }
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

      def page(rows, params, &)
        limit = Payload.page_limit(params["limit"])
        window = rows.drop(cursor_index(rows, params["after"])).first(limit + 1)
        visible = window.first(limit)
        { data: visible.map(&), has_more: more?(window, limit), after: cursor_for(window, visible, limit) }
      end

      def more?(window, limit)
        window.size > limit
      end

      def cursor_for(window, visible, limit)
        return unless more?(window, limit)

        visible.last.id
      end

      def cursor_index(rows, after)
        return 0 if after.blank?

        index = rows.index { |recording| recording.id == after }
        index.nil? ? 0 : index + 1
      end

      def visible_chats
        chats.to_a.select { |recording| viewable?(recording) }
      end

      def chats
        scope = RecordingStudio::Recording.for_root(@root.id).where(recordable_type: Session.name)
        scope = scope.where(parent_recording_id: @page_recording.id) if @page_recording
        scope.order(created_at: :desc)
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
