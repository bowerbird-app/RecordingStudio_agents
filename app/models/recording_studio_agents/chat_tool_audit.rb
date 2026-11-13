# frozen_string_literal: true

module RecordingStudioAgents
  # One row per in-process chat tool call. Argument keys only. Values stay out.
  class ChatToolAudit < ApplicationRecord
    self.table_name = "recording_studio_agents_chat_tool_audits"

    Entry = Data.define(:name, :arguments, :call_id)
    KEY = :recording_studio_agents_chat_recording

    def self.record!(entry, actor:, kind:, outcome:)
      create!(identity(actor).merge(call_fields(entry, kind, outcome)))
    end

    def self.with_chat(recording)
      return yield if recording.nil?

      previous = Thread.current[KEY]
      Thread.current[KEY] = recording
      yield
    ensure
      Thread.current[KEY] = previous if recording
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
        tool_name: entry.name.to_s,
        kind: kind,
        argument_keys: argument_keys(entry.arguments),
        outcome: outcome,
        call_id: entry.call_id.to_s
      }
    end

    def self.argument_keys(arguments)
      return [] unless arguments.is_a?(Hash)

      arguments.each_key.map(&:to_s)
    end

    def self.recording_id(recording)
      return if recording.nil?
      return recording.id if recording.respond_to?(:id)

      recording
    end
    private_class_method :identity, :call_fields, :argument_keys, :recording_id
  end
end
