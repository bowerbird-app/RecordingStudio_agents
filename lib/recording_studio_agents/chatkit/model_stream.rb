# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    class ModelStream
      def initialize(actor, root, recording, turn_tools: nil)
        @actor = actor
        @root = root
        @recording = recording
        @turn_tools = turn_tools || Mcp::TurnTools.build(actor: actor, root: root)
      end

      def play(&)
        @assistant = AssistantTurn.new(@recording.id)
        @saw_text = false
        @shown = ShownLines.new
        finish_stream(Timing.measure("model_stream") { read_stream(&) }, &)
      rescue RecordingStudioAI::Agents::Failure,
             RecordingStudioAI::Errors::UsageDeclined,
             RecordingStudioAI::Errors::ContractValidationError => e
        stopped(e, &)
      end

      def cancel!
        RecordingStudioAI::Agents.cancel(**agent_args)
      rescue StandardError => e
        ErrorLog.call(e, site: "model_stream.cancel")
        nil
      end

      private

      def stopped(error, &)
        ErrorLog.call(error, site: "model_stream.play")
        return yield(UsageNotice.event(thread_id: @recording.id)) if usage_declined?(error)
        return PostedResults.end_if_settled(error) if error.is_a?(RecordingStudioAI::Errors::ContractValidationError)

        yield failure(error.message)
      end

      def usage_declined?(error) = error.is_a?(RecordingStudioAI::Errors::UsageDeclined)

      def finish_stream(result, &)
        calls = pending_calls(result)
        answer_tools(calls, &)
        recover_saved(&) if calls.empty? && !@saw_text
        remember(@assistant)
      end

      def read_stream(&) = RecordingStudioAI::Agents.stream(**agent_args) { |event| emit(event, &) }

      def answer_tools(calls, &)
        return if calls.empty?

        ToolRound.new(actor: @actor, root: @root, chat_recording: @recording, agent_args: agent_args,
                      turn_tools: @turn_tools).run(calls) { |event| emit(event, &) }
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
      rescue RecordingStudioAI::Agents::Failure => e
        ErrorLog.call(e, site: "model_stream.recovered_session")
        nil
      end

      def saved_reply(recovery)
        item = Array(recovery&.items).reverse.find { |entry| reply?(entry) }
        return if item.nil?

        RecordingStudioAI::Providers::StreamEvent.new(type: "message_completed", text: item.text)
      end

      def reply?(entry) = entry.role != "user" && entry.text.present?

      def emit(event, &)
        fresh = fresh_text?(event)
        return if @shown.discard?(event, fresh: fresh)

        open_next if fresh
        @shown.see(event)
        @saw_text = true if text_event?(event)
        @assistant.apply(event).each(&)
        @shown.keep(@assistant.text) if @assistant.savable?
      end

      def fresh_text?(event) = @assistant.savable? && text_event?(event)

      def open_next
        remember(@assistant)
        @assistant = AssistantTurn.new(@recording.id)
        @shown.restart
      end

      def remember(assistant)
        return unless assistant.savable?

        Item.create!(
          id: assistant.item_id, recording: @recording, root_recording: @root, role: "assistant",
          text: assistant.text, status: "done", created_at: assistant.created_at
        )
      end

      def pending_calls(source) = source.respond_to?(:tool_calls) ? Array(source.tool_calls) : []

      def text_event?(event) = %w[text_delta message_completed].include?(event.type.to_s)

      def failure(message) = { type: "error", code: "custom", message: message, allow_retry: true }

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

    # Text already shown in one ModelStream#play. The next play uses a new instance.
    class ShownLines
      ITEM_ID = /\A[A-Za-z0-9_.:-]{1,80}\z/

      def initialize
        @rows = []
        restart
      end

      def restart
        @deltas = false
        @item_id = nil
        @kept = false
      end

      def see(event)
        @deltas = true if event.type.to_s == "text_delta"
        found = item_id(event)
        @item_id = found if found
      end

      def keep(text)
        return if @kept

        @rows << [@item_id, text]
        @kept = true
      end

      def discard?(event, fresh:)
        return false unless drop?(event, fresh: fresh)

        Timing.note_drop
        log_discard(event)
        true
      end

      def drop?(event, fresh:)
        return false unless event.type.to_s == "message_completed"

        text = event.text.to_s
        return false if text.empty?

        id = item_id(event)
        return same_item?(id, text) if id
        return false if !fresh && @deltas

        @rows.any? { |_id, saved| saved == text }
      end

      private

      def same_item?(item_id, text)
        @rows.any? { |saved_id, saved| saved_id == item_id && saved == text }
      end

      def item_id(event)
        metadata = event.metadata
        return if metadata.blank?

        metadata["item_id"].presence
      end

      def safe_id(value)
        text = value.to_s
        text.match?(ITEM_ID) ? text : "none"
      end

      def log_discard(event)
        found = item_id(event)
        item_id = safe_id(found)
        by = found ? "id" : "text"
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger.respond_to?(:info)

        Rails.logger.info("#{ErrorLog::PREFIX} dedupe dropped item_id=#{item_id} by=#{by}")
      rescue StandardError
        nil
      end
    end
  end
end
