# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    class Create < RecordingStudio::Services::BaseService
      include RootGuard
      include Access
      include ChatDraft
      include InstructionsText
      include GlobalKey
      include PersistChat

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
        assign_chat_options(options)
        assign_request_options(options)
      end

      def assign_chat_options(options)
        @title = options[:title]
        @instructions = options[:instructions]
        @profile = options[:profile]
        @purpose = options[:purpose]
        @execution_source = options.fetch(:execution_source, :web)
        @recording_id = options[:recording_id]
        @item_id = options[:item_id]
        @item_created_at = options[:item_created_at]
      end

      def assign_request_options(options)
        @access_grant = options[:access_grant]
        @event_actor = options[:event_actor]
        @metadata = options[:metadata]
        @provider_input = options[:provider_input]
        @turn_tools = options[:turn_tools]
      end

      def perform
        validate!
        found = existing_recording
        return success(found) if found

        reject_global_binding_straggler!
        success(ChatKit::Timing.measure("create_persist") { persist(open_hosted) })
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

      def open_hosted
        args = provider_args
        count = Array(args[:tools]).size
        ChatKit::Timing.measure("create_provider", tools: count) { RecordingStudioAI::Agents.create_session(**args) }
      end

      def provider_args
        tools = (@turn_tools ||= Mcp::TurnTools.build(actor: @actor, root: @root_recording)).definitions
        {
          instructions: instructions, profile: profile, input: model_input, idempotency_key: @idempotency_key,
          purpose: purpose, **provider_override, **attribution
        }.tap { |args| args[:tools] = tools if tools }
      end

      # Recording Studio AI treats a provider argument as an override. The default
      # name on this gem is only for ChatKit readiness, so it is omitted unless
      # the host has allowed that override.
      def provider_override
        name = configuration.provider
        return {} if name.blank?

        allowed = Array(RecordingStudioAI.configuration.allowed_provider_overrides)
        return {} unless allowed.map { |entry| entry.to_s.strip.downcase }.include?(name)

        { provider: name }
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

      def model_input
        return @input if @provider_input.nil? || (@provider_input.is_a?(String) && @provider_input.strip.empty?)

        @provider_input
      end
    end
  end
end
