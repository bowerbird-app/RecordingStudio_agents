# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    class Append < RecordingStudio::Services::BaseService
      include RootGuard
      include ChatLookup

      def initialize(root_recording:, actor:, input:, idempotency_key:, **options)
        super()
        @root_recording = root_recording
        @actor = actor
        @input = input
        @idempotency_key = idempotency_key
        @recording = options[:recording]
        @recording_id = options[:recording_id]
        @execution_source = options.fetch(:execution_source, :web)
        @access_grant = options[:access_grant]
      end

      private

      def perform
        validate!
        recording = require_chat!
        return success(recording) if replay?(recording)

        deliver(recording)
        success(recording)
      end

      def validate!
        ensure_root!(@root_recording)
        ensure_actor!(@actor)
        ensure_key!(@idempotency_key)
        ensure_input!
        raise Error, "chat is required" if @recording.nil? && @recording_id.blank?
      end

      def ensure_input!
        return if @input.is_a?(String) && !@input.strip.empty?

        raise Error, "input must be a non-empty string"
      end

      def replay?(recording)
        item = Item.find_by(root_recording_id: @root_recording.id, idempotency_key: @idempotency_key)
        return false if item.nil?
        return true if item.recording_id == recording.id

        reject_foreign_item!(item)
      end

      def reject_foreign_item!(item)
        ensure_in_root!(item.recording, @root_recording)
        raise Error, "idempotency_key belongs to another chat"
      end

      def deliver(recording)
        send_input(recording)
        remember_item(recording)
        touch_binding(recording)
      end

      def send_input(recording)
        RecordingStudioAI::Agents.send_input(**input_args(recording))
      end

      def input_args(recording)
        {
          session: handle_for(recording), input: @input, idempotency_key: @idempotency_key,
          purpose: recording.recordable.purpose, **attribution(recording)
        }
      end

      def handle_for(recording)
        ProviderSessions.handle(Binding.find_by!(recording: recording), recording.recordable)
      end

      def remember_item(recording)
        Item.create!(item_attributes(recording))
      rescue ActiveRecord::RecordNotUnique
        raise Error, "idempotency_key belongs to another chat" unless replay?(recording)
      end

      def item_attributes(recording)
        {
          id: SecureRandom.uuid, recording: recording, root_recording: @root_recording, role: "user",
          text: @input, status: "done", idempotency_key: @idempotency_key
        }
      end

      def touch_binding(recording)
        Binding.find_by!(recording: recording).update!(
          last_activity_at: Time.current,
          expires_at: Time.current + RecordingStudioAgents.configuration.retention_period,
          preview: @input.to_s.truncate(280)
        )
      end

      def attribution(recording)
        ProviderSessions.attribution(
          root_recording: @root_recording, initiator: @actor, context_recording: recording,
          execution_source: @execution_source
        )
      end
    end
  end
end
