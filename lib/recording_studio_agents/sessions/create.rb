# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    class Create < RecordingStudio::Services::BaseService
      include RootGuard
      include Access
      include ChatDraft
      include GlobalKey

      def initialize(parent_recording:, root_recording:, actor:, input:, **options)
        super()
        @parent_recording = parent_recording
        @root_recording = root_recording
        @actor = actor
        @input = input
        @idempotency_key = options[:idempotency_key]
        assign_options(options)
      end

      private

      def assign_options(options)
        @title = options[:title]
        @instructions = options[:instructions]
        @profile = options[:profile]
        @purpose = options[:purpose]
        @execution_source = options.fetch(:execution_source, :web)
        @access_grant = options[:access_grant]
      end

      def perform
        validate!
        found = existing_recording
        return success(found) if found

        success(persist(open_session))
      end

      def existing_recording
        record = Binding.find_by(root_recording_id: @root_recording.id, create_idempotency_key: @idempotency_key)
        return if record.nil?

        ensure_in_root!(record.recording, @root_recording)
        ensure_access!(record.recording)
        record.recording
      end

      def validate!
        ensure_root!(@root_recording)
        ensure_actor!(@actor)
        ensure_key!(@idempotency_key)
        ensure_input!
        ensure_parent!
        ensure_access!(@parent_recording)
      end

      def ensure_input!
        return if @input.is_a?(String) && !@input.strip.empty?

        raise Error, "input must be a non-empty string"
      end

      def ensure_parent!
        ensure_in_root!(@parent_recording, @root_recording)
        return if RecordingStudio.parent_allowed?(child_type: Session, parent_recording: @parent_recording)

        raise Error, "parent cannot own a chat"
      end

      def open_session
        RecordingStudioAI::Agents.create_session(**provider_args)
      end

      def provider_args
        {
          instructions: instructions, profile: profile, input: @input, idempotency_key: @idempotency_key,
          purpose: purpose, provider: configuration.provider, **attribution
        }
      end

      def persist(hosted)
        Session.transaction { insert_chat(hosted) }
      rescue StandardError => e
        abandon(hosted)
        reraise_binding_conflict!(e)
      end

      def insert_chat(hosted)
        recording = record_chat(hosted)
        insert_binding(recording, hosted)
        insert_item(recording)
        recording
      end

      def record_chat(hosted)
        @root_recording.record(Session, actor: @actor, parent_recording: @parent_recording) do |chat|
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

      def attribution
        ProviderSessions.attribution(
          root_recording: @root_recording, initiator: @actor, context_recording: @parent_recording,
          execution_source: @execution_source
        )
      end

      def configuration
        RecordingStudioAgents.configuration
      end
    end
  end
end
