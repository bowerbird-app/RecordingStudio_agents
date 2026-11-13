# frozen_string_literal: true

require "recording_studio_agents/chat_tool_argument_keys"

module RecordingStudioAgents
  # One row per in-process chat tool call. Argument keys only. Values stay out.
  class ChatToolAudit < ApplicationRecord
    self.table_name = "recording_studio_agents_chat_tool_audits"

    Entry = Data.define(:name, :arguments, :call_id)
    KEY = :recording_studio_agents_chat_recording
    ROUND = :recording_studio_agents_tool_round
    TURN = :recording_studio_agents_provider_turn_id
    RESERVED = :recording_studio_agents_reserved_audit

    def self.record!(entry, actor:, kind:, outcome:)
      create!(row_for(entry, actor, kind, outcome))
    end

    def self.begin!(entry, actor:, kind:)
      record!(entry, actor: actor, kind: kind, outcome: "pending")
    end

    def self.finish!(row, outcome)
      claim_pending!(row, outcome)
    end

    # One update. The caller posts unknown only when this wins.
    def self.claim_unknown!(row)
      claim_pending!(row, "unknown")
    end

    def self.claim_pending!(row, outcome) # rubocop:disable Naming/PredicateMethod -- reports whether the pending update won
      changed = where(id: row.id, outcome: "pending").update_all(outcome: outcome.to_s, updated_at: Time.current)
      row.outcome = outcome.to_s if changed == 1
      log_conflict(row, outcome) unless changed == 1
      changed == 1
    end

    def self.writes_used(turn_id)
      return 0 if turn_id.blank?

      where(provider_turn_id: turn_id.to_s, kind: "write").where.not(outcome: "limited").count
    end

    def self.rounds_used(turn_id)
      return 0 if turn_id.blank?

      where(provider_turn_id: turn_id.to_s).maximum(:round_number).to_i
    end

    def self.with_chat(recording, &block)
      return block.call if recording.nil?

      swap(KEY, recording, &block)
    end

    def self.with_round(number, &)
      swap(ROUND, number, &)
    end

    def self.with_turn(turn_id, &)
      swap(TURN, turn_id, &)
    end

    def self.with_reserved(row, &)
      swap(RESERVED, row, &)
    end

    def self.current_reserved
      Thread.current[RESERVED]
    end

    def self.swap(key, value)
      previous = Thread.current[key]
      Thread.current[key] = value
      yield
    ensure
      Thread.current[key] = previous
    end

    def self.row_for(entry, actor, kind, outcome)
      identity(actor).merge(call_fields(entry, kind, outcome))
    end

    def self.identity(actor)
      {
        occurred_at: Time.current,
        actor_type: actor&.class&.name,
        actor_id: actor&.id&.to_s,
        chat_recording_id: recording_id(Thread.current[KEY])
      }
    end

    def self.call_fields(entry, kind, outcome)
      {
        tool_name: entry.name.to_s, kind: kind, argument_keys: argument_keys(entry.arguments),
        outcome: outcome, call_id: entry.call_id.to_s,
        provider_turn_id: Thread.current[TURN].to_s.presence, round_number: Thread.current[ROUND]
      }
    end

    def self.argument_keys(arguments)
      ChatToolArgumentKeys.list(arguments)
    end

    def self.recording_id(recording)
      return if recording.nil?
      return recording.id if recording.respond_to?(:id)

      recording
    end

    def self.log_conflict(row, outcome)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      current = where(id: row.id).pick(:outcome)
      Rails.logger.warn(
        "Recording Studio Agents: chat tool audit #{row.id} stayed #{current}, so #{outcome} was not stored"
      )
    end
    private_class_method :swap, :row_for, :identity, :call_fields, :argument_keys, :recording_id,
                         :claim_pending!, :log_conflict
  end
end
