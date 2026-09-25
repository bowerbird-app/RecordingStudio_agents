# frozen_string_literal: true

class AddRecordToRecordingStudioAgentsAgentSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_agents_agent_steps, :record_json, :json, null: false, default: {}
  end
end
