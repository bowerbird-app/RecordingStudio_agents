# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # A duplicate call. A live one is omitted. A stale pending row is a failure.
    class JoinedCall
      UNKNOWN = "tool call outcome unknown; it was not re-run"

      def self.entry(audit, call, recovered:)
        row = audit.find_by!(provider_turn_id: call.provider_turn_id.to_s, call_id: call.call_id.to_s)
        stale = stale?(row, recovered)
        WriteBudget::Entry.new(call: call, row: row, joined: !stale, stale: stale)
      end

      def self.stale?(row, recovered)
        return false unless row.outcome == "pending"
        return true if recovered

        row.occurred_at < Time.current - audit_window
      end

      def self.audit_window
        RecordingStudioAgents::ChatToolAudit::PENDING_STALE_AFTER
      end

      def self.omit(call)
        { call_id: call.call_id, turn_id: call.provider_turn_id, joined: true }
      end

      # error matches output so Recording Studio AI posts success: false.
      def self.unknown(call)
        {
          call_id: call.call_id, turn_id: call.provider_turn_id,
          success: false, output: UNKNOWN, error: UNKNOWN
        }
      end
    end

    # One savepoint insert. A duplicate call id joins the row and leaves it alone.
    class AuditInsert
      def self.once(audit, &)
        audit.transaction(requires_new: true, &)
      rescue ActiveRecord::RecordNotUnique
        :joined
      end
    end

    # Write and round limits for one provider turn. A new ToolRound keeps counting.
    class WriteBudget
      # joined and stale stay in memory. The audit row stays the first caller's.
      Entry = Data.define(:call, :row, :joined, :stale)

      def initialize(actor, root, recovered: false)
        @actor = actor
        @root = root
        @recovered = recovered
        @local_writes = Hash.new(0)
        @plain_rounds = 0
      end

      def round_open?(calls)
        turn_id = batch_turn(calls)
        return plain_round? if turn_id.nil?

        TurnLock.with(turn_id) { rounds_left?(turn_id) }
      end

      def answer_round(calls)
        turn_id = batch_turn(calls)
        return plain_answers(calls) if turn_id.nil?

        prepared = TurnLock.with(turn_id) { prepare(calls, turn_id) }
        return :closed if prepared == :closed

        prepared.map { |item| release(item) }
      end

      private

      def plain_round?
        @plain_rounds += 1
        @plain_rounds <= ToolRound::MAX_ROUNDS
      end

      def plain_answers(calls)
        audit.with_round(nil) { calls.map { |call| answer(call) } }
      end

      def prepare(calls, turn_id)
        return :closed unless rounds_left?(turn_id)

        audit.with_round(audit.rounds_used(turn_id) + 1) { calls.map { |call| reserve(call) } }
      end

      def rounds_left?(turn_id)
        audit.rounds_used(turn_id) < ToolRound::MAX_ROUNDS
      end

      def answer(call)
        release(TurnLock.with(call.provider_turn_id) { reserve(call) })
      end

      def reserve(call)
        audit.with_turn(call.provider_turn_id) { over_cap?(call) ? limited(call) : hold(call) }
      end

      def hold(call)
        saved = AuditInsert.once(audit) { audit.begin!(entry_for(call), actor: @actor, kind: kind_of(call)) }
        saved == :joined ? JoinedCall.entry(audit, call, recovered: @recovered) : fresh(call, saved)
      end

      def fresh(call, row)
        Entry.new(call: call, row: row, joined: false, stale: false)
      end

      def release(item)
        return item unless item.is_a?(Entry)
        return JoinedCall.unknown(item.call) if item.stale
        return JoinedCall.omit(item.call) if item.joined

        audit.with_turn(item.call.provider_turn_id) do
          audit.with_reserved(item.row) { Mcp::ChatTools.answer(item.call, actor: @actor, root: @root) }
        end
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

        audit.writes_used(turn_id)
      end

      def remember_blank(call)
        return if call.provider_turn_id.present?

        @local_writes[""] += 1
      end

      def write?(call)
        kind_of(call) == "write"
      end

      def kind_of(call)
        grant = Mcp::ChatTools.installed? ? Mcp::ChatTools.grant_for(@actor, @root) : nil
        Mcp::ChatTools.kind_for(call.name, grant)
      end

      def cap
        RecordingStudioAgents.configuration.mcp_max_writes_per_turn
      end

      def limited(call)
        saved = AuditInsert.once(audit) do
          audit.record!(entry_for(call), actor: @actor, kind: "write", outcome: "limited")
        end
        return JoinedCall.entry(audit, call, recovered: @recovered) if saved == :joined

        { call_id: call.call_id, turn_id: call.provider_turn_id, error: "write limit reached" }
      end

      def entry_for(call)
        audit::Entry.new(name: call.name, arguments: call.arguments, call_id: call.call_id)
      end

      def audit
        RecordingStudioAgents::ChatToolAudit
      end
    end
  end
end
