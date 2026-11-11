# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # Runs the function calls a hosted turn is waiting on, then posts the results.
    class ToolRound
      MAX_ROUNDS = 8

      def initialize(actor:, root:, agent_args:, &emit)
        @actor = actor
        @root = root
        @agent_args = agent_args
        @emit = emit
      end

      def run(calls, &emit)
        @emit = emit
        delivered = nil
        MAX_ROUNDS.times do
          break if calls.empty?

          delivered = deliver(answers(calls))
          calls = pending_calls(delivered)
        end
        return delivered if calls.empty?

        deliver(calls.map { |call| refusal(call, "too many tool calls") })
      end

      private

      def answers(calls)
        calls.map { |call| Mcp::ChatTools.answer(call, actor: @actor, root: @root) }
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
