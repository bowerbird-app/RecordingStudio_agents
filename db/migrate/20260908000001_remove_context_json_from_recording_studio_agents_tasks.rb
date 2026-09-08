# frozen_string_literal: true

class RemoveContextJsonFromRecordingStudioAgentsTasks < ActiveRecord::Migration[8.1]
  def change
    remove_column :recording_studio_agents_tasks, :context_json, :json, default: {}, null: false
  end
end
