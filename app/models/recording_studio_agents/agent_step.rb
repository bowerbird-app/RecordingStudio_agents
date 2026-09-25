# frozen_string_literal: true

module RecordingStudioAgents
  class AgentStep < ApplicationRecord
    self.table_name = "recording_studio_agents_agent_steps"

    STATUSES = %w[planned started completed failed awaiting_confirmation unresolved].freeze
    ACTION_TYPES = %w[reason decide tool deliver handoff arguments].freeze

    belongs_to :agent_run, class_name: "RecordingStudioAgents::AgentRun"

    validates :sequence, :action_type, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :action_type, inclusion: { in: ACTION_TYPES }
    validates :sequence, uniqueness: { scope: :agent_run_id }
  end
end
