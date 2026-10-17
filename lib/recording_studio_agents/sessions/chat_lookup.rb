# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module ChatLookup
      private

      def require_chat!
        recording = chat_in_root!
        raise Error, "recording is not a chat" unless chat_recording?(recording)

        recording
      end

      def optional_chat
        return present_chat if @recording

        chats_in_root.find_by(id: @recording_id)
      end

      def present_chat
        ensure_in_root!(@recording, @root_recording)
        raise Error, "recording is not a chat" unless chat_recording?(@recording)

        @recording
      end

      def chat_in_root!
        recording = @recording || chats_in_root.find_by(id: @recording_id)
        raise Error, "chat was not found" if recording.nil?

        ensure_in_root!(recording, @root_recording)
        recording
      end

      def chats_in_root
        RecordingStudio::Recording.for_root(@root_recording.id).where(recordable_type: Session.name)
      end

      def chat_recording?(recording)
        recording.recordable_type == Session.name
      end
    end
  end
end
