# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module PersistChat
      private

      def persist(hosted)
        Session.transaction(requires_new: true) { insert_chat(hosted) }
      rescue StandardError => e
        resume_after_binding_insert(hosted, e)
      end

      def insert_chat(hosted)
        recording = record_chat(hosted)
        insert_binding(recording, hosted)
        insert_item(recording)
        recording
      end

      def record_chat(hosted)
        @root_recording.record(
          Session,
          actor: @event_actor || @actor,
          metadata: @metadata || {},
          parent_recording: @parent_recording
        ) do |chat|
          assign_chat(chat, hosted)
        end
      end

      def insert_binding(recording, hosted)
        Binding.create!(binding_attributes(recording, hosted))
      end

      def insert_item(recording)
        Item.create!(item_attributes.merge(recording: recording, root_recording: @root_recording))
      end

      def abandon(hosted)
        return if hosted.nil?

        RecordingStudioAI::Agents.delete_session(session: hosted, purpose: purpose, **attribution)
      rescue RecordingStudioAI::Agents::Failure
        nil
      end
    end
  end
end
