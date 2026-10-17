# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    class Close < RecordingStudio::Services::BaseService
      include RootGuard
      include ChatLookup

      def initialize(root_recording:, actor: nil, **options)
        super()
        @root_recording = root_recording
        @actor = actor
        @recording = options[:recording]
        @recording_id = options[:recording_id]
        @system = options.fetch(:system, false)
        @execution_source = options.fetch(:execution_source, (@system ? :scheduled : :web))
      end

      private

      def perform
        ensure_root!(@root_recording)
        recording = find_chat
        return success(nil) if recording.nil?

        delete_provider!(recording)
        purge!(recording)
        success(recording.id)
      end

      def find_chat
        return system_chat if @system

        ensure_actor!(@actor)
        optional_chat
      end

      def system_chat
        recording = @recording || chats_in_root.find_by(id: @recording_id)
        return if recording.nil?

        ensure_in_root!(recording, @root_recording)
        raise Error, "recording is not a chat" unless chat_recording?(recording)

        recording
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
            root_recording: @root_recording, initiator: close_initiator, context_recording: recording,
            execution_source: @execution_source, initiator_kind: (@system ? :system : nil)
          )
        }
      end

      def close_initiator
        @system ? ProviderSessions::SYSTEM_INITIATOR : @actor
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
