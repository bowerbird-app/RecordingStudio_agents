# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # Counts write-tool calls for one assistant reply. Reads do not count.
    class WriteBudget
      def initialize(actor, root)
        @actor = actor
        @root = root
        @writes = 0
      end

      def answer(call)
        return limited(call) if over_cap?(call)

        Mcp::ChatTools.answer(call, actor: @actor, root: @root)
      end

      private

      def over_cap?(call)
        return false unless write?(call)
        return true if @writes >= cap

        @writes += 1
        false
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
