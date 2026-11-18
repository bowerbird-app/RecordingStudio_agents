# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # Runs the function calls a hosted turn is waiting on, then posts the results.
    class ToolRound
      MAX_ROUNDS = 8

      def initialize(actor:, root:, agent_args:, chat_recording: nil, turn_tools: nil, &emit)
        @actor = actor
        @root = root
        @agent_args = agent_args
        @chat_recording = chat_recording
        @turn_tools = turn_tools || Mcp::TurnTools.build(actor: actor, root: root)
        @budget = WriteBudget.new(actor, root, @turn_tools)
        @emit = emit
      end

      def run(calls, &emit)
        @emit = emit
        delivered = rounds(calls)
        waiting = delivered.nil? ? Array(calls) : PostedResults.pending(delivered)
        return delivered if waiting.empty?

        finish_over_cap(waiting)
      end

      private

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

        timed_step(calls, delivered)
      end

      def timed_step(calls, delivered)
        stamp = Timing.mark
        answers_ms = nil
        model_ms = nil
        step_result, answers_ms, model_ms = timed_parts(calls, delivered)
        step_result
      ensure
        Timing.round(next_round, stamp, answers_ms: answers_ms, model_ms: model_ms) if stamp
      end

      def timed_parts(calls, delivered)
        answers_ms, results = timed_answers(calls)
        return [[delivered, calls, true], answers_ms, nil] if results == :closed

        model_ms, delivered = timed_model(results)
        [[delivered, PostedResults.pending(delivered), false], answers_ms, model_ms]
      end

      def timed_answers(calls)
        started = Timing.mark
        results = answers(calls)
        [Timing.elapsed_ms(started), results]
      end

      def timed_model(results)
        started = Timing.mark
        delivered = deliver(results)
        [Timing.elapsed_ms(started), delivered]
      end

      def next_round
        @round = @round.to_i + 1
      end

      def finish_over_cap(calls)
        delivered = deliver(calls.map { |call| refusal(call, "too many tool calls") })
        return delivered if PostedResults.pending(delivered).empty?

        abandon(delivered)
      end

      def abandon(delivered)
        cancel_run
        @emit.call(RecordingStudioAI::Providers::StreamEvent.new(type: "failed"))
        delivered
      end

      def cancel_run
        RecordingStudioAI::Agents.cancel(**@agent_args)
      rescue RecordingStudioAI::Agents::Failure => e
        ErrorLog.call(e, site: "tool_round.cancel_run") || nil
      end

      def answers(calls)
        RecordingStudioAgents::ChatToolAudit.with_chat(@chat_recording) { @budget.answer_round(calls) }
      end

      def refusal(call, message)
        { call_id: call.call_id, turn_id: call.provider_turn_id, error: message }
      end

      def deliver(results)
        poster.deliver(results)
      end

      def retry_post(results, error)
        poster.retry_post(results, error)
      end

      def poster
        ToolPost.new(@agent_args, @emit)
      end
    end

    # Posts tool results. A timeout reads the pending calls again before a retry.
    class ToolPost
      def initialize(agent_args, emit)
        @agent_args = agent_args
        @emit = emit
      end

      def deliver(results)
        postable = PostedResults.list(results)
        return PostedResults.quiet_turn if postable == :quiet

        post(postable)
      rescue RecordingStudioAI::Agents::Failure => e
        ErrorLog.call(e, site: "tool_round.deliver")
        raise unless e.error.respond_to?(:category) && e.error.category.to_s == "timeout"

        retry_post(postable, e)
      rescue RecordingStudioAI::Errors::ContractValidationError => e
        ErrorLog.call(e, site: "tool_round.deliver")
        PostedResults.end_if_settled(e)
      end

      def retry_post(results, error)
        pending = reread_pending
        raise error if pending.nil?

        narrowed = align(results, pending)
        return continue if narrowed.empty?

        post(narrowed)
      rescue RecordingStudioAI::Errors::ContractValidationError => e
        ErrorLog.call(e, site: "tool_round.retry_post")
        pending = reread_pending
        raise error if pending.nil? || pending.any?

        continue
      end

      private

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
      rescue RecordingStudioAI::Agents::Failure => e
        ErrorLog.call(e, site: "tool_round.reread_pending") || nil
      end

      def align(results, calls)
        by_id = calls.index_by(&:call_id)
        results.filter_map do |result|
          call = by_id[result[:call_id]]
          next if call.nil?

          result.merge(turn_id: call.provider_turn_id)
        end
      end
    end
  end
end
