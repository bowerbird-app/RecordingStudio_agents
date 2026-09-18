# frozen_string_literal: true

class CreateRecordingStudioAgentsEnablements < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_agents_enablements do |t|
      t.string :agent_key, null: false
      t.integer :agent_version, null: false
      t.boolean :enabled, null: false
      t.timestamps
    end

    add_index :recording_studio_agents_enablements,
              %i[agent_key agent_version],
              unique: true,
              name: "index_rsa_enablements_on_agent"
  end
end
