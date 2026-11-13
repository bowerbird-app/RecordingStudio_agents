# frozen_string_literal: true

require "digest"

module RecordingStudioAgents
  module ChatKit
    # One lock per provider turn. The write count and the pending audit insert share it.
    module TurnLock
      module_function

      def with(turn_id)
        return yield if turn_id.blank?

        RecordingStudioAgents::ChatToolAudit.transaction do
          lock_turn(turn_id)
          yield
        end
      end

      # Postgres advisory locks are transaction scoped. SQLite has none. Rails opens a
      # SQLite transaction with BEGIN IMMEDIATE, which reserves the database for writers.
      def lock_turn(turn_id)
        connection = RecordingStudioAgents::ChatToolAudit.connection
        return unless connection.adapter_name.match?(/postgre/i)

        connection.raw_connection.exec_params("SELECT pg_advisory_xact_lock($1)", [advisory_key(turn_id)]).clear
      end

      def advisory_key(turn_id)
        Digest::SHA256.digest("recording_studio_agents:turn:#{turn_id}").unpack1("q>")
      end
    end
  end
end
