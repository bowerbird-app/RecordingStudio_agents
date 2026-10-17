# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module RootGuard
      private

      def ensure_root!(recording)
        return if recording.respond_to?(:root?) && recording.root?

        raise Error, "root_recording must be a root recording"
      end

      def ensure_in_root!(recording, root)
        return if recording&.root_recording_id.present? && recording.root_recording_id == root.id

        raise IsolationError, "recording is outside this root"
      end

      def ensure_actor!(actor)
        raise Error, "actor is required" if actor.blank?
      end

      def ensure_key!(key)
        return if key.is_a?(String) && !key.strip.empty? && key.length <= 255

        raise Error, "idempotency_key must be a non-empty string"
      end
    end
  end
end
