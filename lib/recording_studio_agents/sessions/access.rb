# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module Access
      private

      def ensure_access!(recording)
        return if RecordingStudioAccessible.authorized?(actor: @actor, recording: recording, role: :edit)

        raise Error, "actor cannot access this recording"
      end
    end
  end
end
