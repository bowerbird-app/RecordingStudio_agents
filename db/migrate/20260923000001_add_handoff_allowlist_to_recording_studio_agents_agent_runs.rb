# frozen_string_literal: true

class AddHandoffAllowlistToRecordingStudioAgentsAgentRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_agents_agent_runs, :handoff_allowlist_json, :json, null: false, default: []
  end
end
