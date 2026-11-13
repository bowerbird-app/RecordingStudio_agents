# frozen_string_literal: true

require "digest"

module RecordingStudioAgents
  module ChatKit
    # PostgreSQL advisory lock for one provider turn. The write count and the
    # pending audit insert share it. The audit table is jsonb, so this lock is
    # not implemented for other adapters.
    module TurnLock
      module_function

      # The lock lasts until the transaction that owns it commits. This opens
      # that transaction when the caller has none. An outer transaction is
      # joined, and the lock then lasts until that outer transaction commits,
      # not when this method returns.
      def with(turn_id)
        return yield if turn_id.blank?

        RecordingStudioAgents::ChatToolAudit.transaction do
          lock_turn(turn_id)
          yield
        end
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
