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
        actor = recording&.first_event&.actor
        return if recording.nil? || actor.blank? || recording.root_recording.nil?

        Close.call(
          root_recording: recording.root_recording, recording: recording, actor: actor, execution_source: :scheduled
        ).value
      rescue Error, RecordingStudioAI::Agents::Failure
        nil
      end
    end
  end
end
