# frozen_string_literal: true

module RecordingStudioAgents
  class Task < ApplicationRecord
    self.table_name = "recording_studio_agents_tasks"

    has_many :agent_runs, class_name: "RecordingStudioAgents::AgentRun", dependent: :restrict_with_exception

    validates :task_key, :goal, :input_digest, :root_recording_id, presence: true
  end
end
