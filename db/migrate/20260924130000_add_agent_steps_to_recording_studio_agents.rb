# frozen_string_literal: true

class AddAgentStepsToRecordingStudioAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_agents_agent_runs, :working_state_json, :json, null: false, default: {}

    create_table :recording_studio_agents_agent_steps do |t|
      t.references :agent_run, null: false, foreign_key: { to_table: :recording_studio_agents_agent_runs }, index: false
      t.integer :sequence, null: false
      t.string :status, null: false
      t.string :action_type, null: false
      t.string :candidate_id
      t.string :tool_key
      t.integer :tool_version
      t.string :argument_digest
      t.text :observation_summary
      t.string :observation_digest
      t.boolean :progress_made
      t.json :controller_outcome
      t.bigint :recording_studio_ai_run_id
      t.boolean :repeatable, null: false, default: false
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :recording_studio_agents_agent_steps,
              %i[agent_run_id sequence],
              unique: true,
              name: "index_rsa_steps_on_run_and_sequence"
  end
end
