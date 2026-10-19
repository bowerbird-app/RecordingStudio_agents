# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module Access
      private

      def ensure_access!(recording, role: :edit)
        return grant_access!(recording, role) if @access_grant
        return if accessible?(recording, role)

        raise AccessDeniedError, "actor cannot access this recording"
      end

      def grant_access!(recording, role)
        @access_grant.authorize!(recording: recording, role: role)
      end

      def accessible?(recording, role)
        RecordingStudioAccessible.authorized?(actor: @actor, recording: recording, role: role)
      end
    end
  end
end
