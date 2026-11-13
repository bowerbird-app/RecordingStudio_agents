# frozen_string_literal: true

require "digest"

module RecordingStudioAgents
  module ChatKit
    # PostgreSQL advisory lock for one provider turn. The write count and the
    # pending audit insert share it. The audit table is jsonb, so this lock is
    # not implemented for other adapters.
    module TurnLock
      module_function

      # Hosts must not run a chat tool round inside an open transaction. This
      # opens the lock transaction itself, and the lock ends when that transaction
      # commits, before the tool runs. An outer transaction would keep the lock
      # until the outer transaction commits. Tests may join one, because they use
      # transactional fixtures. Anywhere else, an open transaction raises.
      def with(turn_id)
        return yield if turn_id.blank?

        refuse_outer_transaction!
        RecordingStudioAgents::ChatToolAudit.transaction do
          lock_turn(turn_id)
          yield
        end
      end

      def check_adapter!
        return if RecordingStudioAgents.configuration.mcp_tools == :off

        connection = RecordingStudioAgents::ChatToolAudit.connection
        raise unsupported_adapter unless postgres?(connection)
      end

      def refuse_outer_transaction!
        return if Rails.env.test?
        return if RecordingStudioAgents::ChatToolAudit.connection.open_transactions.zero?

        raise RecordingStudioAgents::Error, "chat tool rounds must not run inside an open transaction"
      end

      def lock_turn(turn_id)
        connection = RecordingStudioAgents::ChatToolAudit.connection
        raise unsupported_adapter unless postgres?(connection)

        key = Integer(advisory_key(turn_id))
        connection.select_value("SELECT pg_advisory_xact_lock(#{key})::text")
      end

      def advisory_key(turn_id)
        Digest::SHA256.digest("recording_studio_agents:turn:#{turn_id}").unpack1("q>")
      end

      def postgres?(connection)
        connection.adapter_name.match?(/postgre/i)
      end

      def unsupported_adapter
        RecordingStudioAgents::Error.new("chat tool turn locks require PostgreSQL")
      end
    end
  end
end
