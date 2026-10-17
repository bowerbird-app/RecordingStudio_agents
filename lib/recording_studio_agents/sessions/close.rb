# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    class Close < RecordingStudio::Services::BaseService
      include RootGuard
      include ChatLookup

      def initialize(root_recording:, actor:, **options)
        super()
        @root_recording = root_recording
        @actor = actor
        @recording = options[:recording]
        @recording_id = options[:recording_id]
        @execution_source = options.fetch(:execution_source, :web)
      end

      private

      def perform
        ensure_root!(@root_recording)
        ensure_actor!(@actor)
        recording = optional_chat
        return success(nil) if recording.nil?

        delete_provider!(recording)
        purge!(recording)
        success(recording.id)
      end

      def delete_provider!(recording)
        binding_record = Binding.find_by(recording_id: recording.id)
        return if binding_record.nil? || binding_record.provider_session_id.blank?

        RecordingStudioAI::Agents.delete_session(**delete_args(recording, binding_record))
      rescue RecordingStudioAI::Agents::Failure => e
        raise unless ProviderSessions.gone?(e)
      end

      def delete_args(recording, binding_record)
        {
          session: ProviderSessions.handle(binding_record, recording.recordable),
          purpose: recording.recordable.purpose,
          **ProviderSessions.attribution(
            root_recording: @root_recording, initiator: @actor, context_recording: recording,
            execution_source: @execution_source
          )
        }
      end

      def purge!(recording)
        recording.child_recordings.to_a.each { |child| purge!(child) }
        snapshots = recording.recordables
        clear_rows(recording)
        recording.destroy!
        delete_snapshots(snapshots)
      end

      def delete_snapshots(snapshots)
        snapshots.group_by(&:class).each do |klass, records|
          klass.where(id: records.map(&:id)).delete_all
        end
      end

      def clear_rows(recording)
        Item.where(recording_id: recording.id).delete_all
        Binding.where(recording_id: recording.id).delete_all
      end
    end
  end
end
