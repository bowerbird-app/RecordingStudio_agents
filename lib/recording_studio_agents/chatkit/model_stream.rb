# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    class ModelStream
      def initialize(actor, root, recording)
        @actor = actor
        @root = root
        @recording = recording
      end

      def play(&block)
        assistant = AssistantTurn.new(@recording.id)
        recover(assistant, &block) unless stream(assistant, &block)
        remember(assistant)
      rescue RecordingStudioAI::Agents::Failure => e
        block.call(failure(e.message))
      end

      def cancel!
        RecordingStudioAI::Agents.cancel(**agent_args)
      rescue StandardError
        nil
      end

      private

      def stream(assistant, &)
        saw = false
        RecordingStudioAI::Agents.stream(**agent_args) do |event|
          saw = true if text_event?(event)
          assistant.apply(event).each(&)
        end
        saw
      end

      def recover(assistant, &)
        saved = saved_reply
        return if saved.nil?

        assistant.apply(saved).each(&)
      end

      def saved_reply
        item = recovered_item
        return if item.nil?

        RecordingStudioAI::Providers::StreamEvent.new(type: "message_completed", text: item.text)
      end

      def recovered_item
        recovery = RecordingStudioAI::Agents.recover(**agent_args)
        Array(recovery&.items).reverse.find { |entry| reply?(entry) }
      rescue StandardError
        nil
      end

      def reply?(entry)
        entry.role != "user" && entry.text.present?
      end

      def remember(assistant)
        return unless assistant.savable?

        Item.create!(
          id: assistant.item_id, recording: @recording, role: "assistant", text: assistant.text, status: "done",
          created_at: assistant.created_at
        )
      end

      def text_event?(event)
        %w[text_delta message_completed].include?(event.type.to_s)
      end

      def failure(message)
        { type: "error", code: "custom", message: message, allow_retry: true }
      end

      def agent_args
        recordable = @recording.recordable
        {
          session: ProviderSessions.handle(Binding.find_by!(recording: @recording), recordable),
          purpose: recordable.purpose,
          **ProviderSessions.attribution(
            root_recording: @root, initiator: @actor, context_recording: @recording, execution_source: :web
          )
        }
      end
    end
  end
end
