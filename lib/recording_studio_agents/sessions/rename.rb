# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    class Rename < RecordingStudio::Services::BaseService
      include RootGuard
      include ChatLookup

      def initialize(root_recording:, actor:, title:, **options)
        super()
        @root_recording = root_recording
        @actor = actor
        @title = title
        @recording = options[:recording]
        @recording_id = options[:recording_id]
      end

      private

      def perform
        validate!
        success(revise(require_chat!))
      end

      def validate!
        ensure_root!(@root_recording)
        ensure_actor!(@actor)
        raise Error, "chat is required" if @recording.nil? && @recording_id.blank?
        return if @title.is_a?(String) && !@title.strip.empty?

        raise Error, "title must be a non-empty string"
      end

      def revise(recording)
        @root_recording.revise(recording, actor: @actor) { |chat| chat.title = @title }
      end
    end
  end
end
