# frozen_string_literal: true

class AddSelectedSkillsToAgentRuns < ActiveRecord::Migration[8.1]
  def change
    change_table :recording_studio_agents_agent_runs do |t|
      t.json :selected_skills_json, null: false, default: []
      t.string :skill_pack_key
      t.integer :skill_pack_version
    end
  end
end
