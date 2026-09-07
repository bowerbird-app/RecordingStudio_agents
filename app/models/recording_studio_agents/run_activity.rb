# frozen_string_literal: true

module RecordingStudioAgents
  class RunActivity < ApplicationRecord
    self.table_name = "recording_studio_agents_run_activities"
    self.record_timestamps = false

    KINDS = Persistence::RunLedger::ACTIVITY_KEYS.keys.freeze

    belongs_to :agent_run, class_name: "RecordingStudioAgents::AgentRun"

    validates :kind, inclusion: { in: KINDS }
    validates :sequence, :occurred_at, presence: true
    validate :data_keys_allowlisted

    private

    def data_keys_allowlisted
      allowed = Persistence::RunLedger::ACTIVITY_KEYS[kind]
      return if allowed.nil?

      extras = data.stringify_keys.keys - allowed
      errors.add(:data, "contains #{extras.join(', ')}") if extras.any?
    end
  end
end
