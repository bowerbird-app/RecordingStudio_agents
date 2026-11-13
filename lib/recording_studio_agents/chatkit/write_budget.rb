# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # Write and round limits for one provider turn. A new ToolRound keeps counting.
    class WriteBudget
      def initialize(actor, root)
        @actor = actor
        @root = root
        @local_writes = Hash.new(0)
        @plain_rounds = 0
      end

      def round_open?(calls)
        turn_id = batch_turn(calls)
        return plain_round? if turn_id.nil?

        RecordingStudioAgents::ChatToolAudit.rounds_used(turn_id) < ToolRound::MAX_ROUNDS
      end

      def answer_round(calls)
        RecordingStudioAgents::ChatToolAudit.with_round(next_round(calls)) do
          calls.map { |call| answer(call) }
        end
      end

      def answer(call)
        RecordingStudioAgents::ChatToolAudit.with_turn(call.provider_turn_id) do
          over_cap?(call) ? limited(call) : Mcp::ChatTools.answer(call, actor: @actor, root: @root)
        end
      end

      private

      def plain_round?
        @plain_rounds += 1
        @plain_rounds <= ToolRound::MAX_ROUNDS
      end

      def next_round(calls)
        turn_id = batch_turn(calls)
        return if turn_id.nil?

        RecordingStudioAgents::ChatToolAudit.rounds_used(turn_id) + 1
      end

      def batch_turn(calls)
        calls.first&.provider_turn_id.presence
      end

      def over_cap?(call)
        return false unless write?(call)
        return true if writes_used(call) >= cap

        remember_blank(call)
        false
      end

      def writes_used(call)
        turn_id = call.provider_turn_id
        return @local_writes[turn_id.to_s] if turn_id.blank?

        RecordingStudioAgents::ChatToolAudit.writes_used(turn_id)
      end

      def remember_blank(call)
        return if call.provider_turn_id.present?

        @local_writes[""] += 1
      end

      def write?(call)
        grant = Mcp::ChatTools.installed? ? Mcp::ChatTools.grant_for(@actor, @root) : nil
        Mcp::ChatTools.kind_for(call.name, grant) == "write"
      end

      def cap
        RecordingStudioAgents.configuration.mcp_max_writes_per_turn
      end

      def limited(call)
        entry = RecordingStudioAgents::ChatToolAudit::Entry.new(
          name: call.name, arguments: call.arguments, call_id: call.call_id
        )
        RecordingStudioAgents::ChatToolAudit.record!(
          entry, actor: @actor, kind: "write", outcome: "limited"
        )
        { call_id: call.call_id, turn_id: call.provider_turn_id, error: "write limit reached" }
      end
    end
  end
end
