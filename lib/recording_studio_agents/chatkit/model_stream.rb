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
        @assistant = AssistantTurn.new(@recording.id)
        @saw_text = false
        result = read_stream(&block)
        answer_tools(pending_calls(result), &block)
        recover_saved(&block) if pending_calls(result).empty? && !@saw_text
        remember(@assistant)
      rescue RecordingStudioAI::Agents::Failure => e
        block.call(failure(e.message))
      end

      def cancel!
        RecordingStudioAI::Agents.cancel(**agent_args)
      rescue StandardError
        nil
      end

      private

      def read_stream(&block)
        RecordingStudioAI::Agents.stream(**agent_args) { |event| emit(event, &block) }
      end

      def answer_tools(calls, &)
        return if calls.empty?

        tool_round.run(calls) { |event| emit(event, &) }
      end

      def recover_saved(&)
        recovery = recovered_session
        return if recovery.nil?

        calls = pending_calls(recovery)
        return answer_tools(calls, &) if calls.any?

        saved = saved_reply(recovery)
        return if saved.nil?

        emit(saved, &)
      end

      def recovered_session
        RecordingStudioAI::Agents.recover(**agent_args)
      rescue RecordingStudioAI::Agents::Failure
        nil
      end

      def saved_reply(recovery)
        item = Array(recovery&.items).reverse.find { |entry| reply?(entry) }
        return if item.nil?

        RecordingStudioAI::Providers::StreamEvent.new(type: "message_completed", text: item.text)
      end

      def reply?(entry)
        entry.role != "user" && entry.text.present?
      end

      def emit(event, &)
        if @assistant.savable? && text_event?(event)
          remember(@assistant)
          @assistant = AssistantTurn.new(@recording.id)
        end
        @saw_text = true if text_event?(event)
        @assistant.apply(event).each(&)
      end

      def remember(assistant)
        return unless assistant.savable?

        Item.create!(
          id: assistant.item_id, recording: @recording, root_recording: @root, role: "assistant",
          text: assistant.text, status: "done", created_at: assistant.created_at
        )
      end

      def tool_round
        ToolRound.new(actor: @actor, root: @root, chat_recording: @recording, agent_args: agent_args)
      end

      def pending_calls(source)
        return [] unless source.respond_to?(:tool_calls)

        Array(source.tool_calls)
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
