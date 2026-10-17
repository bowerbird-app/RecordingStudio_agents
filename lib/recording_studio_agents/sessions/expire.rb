# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    class Expire < RecordingStudio::Services::BaseService
      private

      def perform
        closed = []
        Binding.expired.find_each { |binding_record| closed << close_binding(binding_record) }
        success(closed.compact)
      end

      def close_binding(binding_record)
        recording = binding_record.recording
        root = recording&.root_recording
        return if recording.nil? || root.nil?

        Close.call(root_recording: root, recording: recording, system: true).value
      rescue Error, RecordingStudioAI::Agents::Failure
        nil
      end
    end
  end
end
