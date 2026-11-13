# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # Runs the function calls a hosted turn is waiting on, then posts the results.
    class ToolRound
      MAX_ROUNDS = 8

      def initialize(actor:, root:, agent_args:, chat_recording: nil, &emit)
        @actor = actor
        @root = root
        @agent_args = agent_args
        @chat_recording = chat_recording
        @budget = WriteBudget.new(actor, root)
        @emit = emit
      end

      def run(calls, &emit)
        @emit = emit
        delivered = rounds(calls)
        waiting = delivered.nil? ? Array(calls) : pending_calls(delivered)
        return delivered if waiting.empty?

        finish_over_cap(waiting)
      end

      private

      # Earlier rounds for this provider turn count. The in-process loop is only a backstop.
      def rounds(calls)
        delivered = nil
        MAX_ROUNDS.times do
          delivered, calls, stop = step(calls, delivered)
          break if stop
        end
        delivered
      end

      def step(calls, delivered)
        return [delivered, calls, true] if calls.empty? || !@budget.round_open?(calls)

        results = answers(calls)
        return [delivered, calls, true] if results == :closed

        delivered = deliver(results)
        [delivered, pending_calls(delivered), false]
      end

      def finish_over_cap(calls)
        delivered = deliver(calls.map { |call| refusal(call, "too many tool calls") })
        return delivered if pending_calls(delivered).empty?

        abandon(delivered)
      end

      def abandon(delivered)
        cancel_run
        @emit.call(RecordingStudioAI::Providers::StreamEvent.new(type: "failed"))
        delivered
      end

      def cancel_run
        RecordingStudioAI::Agents.cancel(**@agent_args)
      rescue RecordingStudioAI::Agents::Failure
        nil
      end

      def answers(calls)
        RecordingStudioAgents::ChatToolAudit.with_chat(@chat_recording) { @budget.answer_round(calls) }
      end

      def refusal(call, message)
        { call_id: call.call_id, turn_id: call.provider_turn_id, error: message }
      end

      def deliver(results)
        post(results)
      rescue RecordingStudioAI::Agents::Failure => e
        raise unless timeout?(e)

        retry_post(results, e)
      end

      # A timeout can mean the result post is still in flight. Read the pending
      # calls again and resend only the ones the provider still lists.
      def retry_post(results, error)
        pending = reread_pending
        raise error if pending.nil?

        narrowed = align(results, pending)
        return continue if narrowed.empty?

        post(narrowed)
      rescue RecordingStudioAI::Errors::ContractValidationError
        pending = reread_pending
        raise error if pending.nil? || pending.any?

        continue
      end

      def post(results)
        return if results.empty?

        RecordingStudioAI::Agents.submit_tool_results(**@agent_args, results: results) do |event|
          @emit.call(event)
        end
      end

      def continue
        RecordingStudioAI::Agents.stream(**@agent_args) { |event| @emit.call(event) }
      end

      def reread_pending
        recovery = RecordingStudioAI::Agents.recover(**@agent_args)
        Array(recovery&.tool_calls)
      rescue RecordingStudioAI::Agents::Failure
        nil
      end

      def align(results, calls)
        by_id = calls.index_by(&:call_id)
        results.filter_map do |result|
          call = by_id[result[:call_id]]
          next if call.nil?

          result.merge(turn_id: call.provider_turn_id)
        end
      end

      def pending_calls(source)
        return [] unless source.respond_to?(:tool_calls)

        Array(source.tool_calls)
      end

      def timeout?(error)
        error.error.respond_to?(:category) && error.error.category.to_s == "timeout"
      end
    end
  end
end
