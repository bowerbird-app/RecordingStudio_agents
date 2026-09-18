# frozen_string_literal: true

module RecordingStudioAgents
  class AgentEnablement < ApplicationRecord
    self.table_name = "recording_studio_agents_enablements"

    validates :agent_key, presence: true
    validates :agent_version, presence: true
    validates :enabled, inclusion: { in: [true, false] }
  end
end
