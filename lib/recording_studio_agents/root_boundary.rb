# frozen_string_literal: true

module RecordingStudioAgents
  module RootBoundary
    module_function

    def contained?(recording, root_recording)
      return false if recording.nil? || root_recording.nil?

      root_id = identifier(root_recording)
      identifier(recording) == root_id ||
        (recording.respond_to?(:root_recording_id) && recording.root_recording_id == root_id)
    end

    def identifier(value)
      value.respond_to?(:id) ? value.id : value
    end
  end
end
