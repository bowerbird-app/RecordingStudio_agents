# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module ChatDraft
      private

      def assign_chat(chat, hosted)
        chat.title = @title
        chat.status = "active"
        chat.model = required_model(hosted)
        chat.profile = hosted.profile
        chat.purpose = purpose
        chat.instructions = instructions
      end

      def binding_attributes(recording, hosted)
        {
          recording: recording, root_recording: @root_recording,
          provider: hosted.provider.to_s, provider_session_id: hosted.provider_session_id,
          last_activity_at: Time.current, expires_at: expires_at, preview: preview,
          create_idempotency_key: @idempotency_key
        }
      end

      def item_attributes
        {
          id: SecureRandom.uuid, recording_id: nil, role: "user", text: @input, status: "done",
          idempotency_key: @idempotency_key
        }
      end

      def required_model(hosted)
        model = hosted.model.to_s
        raise Error, "provider session did not include a model" if model.empty?

        model
      end

      def instructions
        return if @instructions.is_a?(String) && @instructions.strip.empty?

        @instructions || configuration.instructions
      end

      def profile
        (@profile || configuration.default_profile).to_sym
      end

      def purpose
        (@purpose || configuration.purpose).to_s
      end

      def preview
        @input.to_s.truncate(280)
      end

      def expires_at
        Time.current + configuration.retention_period
      end

      def configuration
        RecordingStudioAgents.configuration
      end
    end
  end
end
