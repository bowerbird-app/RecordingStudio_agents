# frozen_string_literal: true

class CreateRecordingStudioAgentsTables < ActiveRecord::Migration[8.1]
  def change
    recording_id_type = recording_identifier_type

    create_table :recording_studio_agents_tasks do |t|
      t.column :root_recording_id, recording_id_type, null: false
      t.column :context_recording_id, recording_id_type
      t.string :task_key, null: false
      t.text :goal, null: false
      t.json :context_json, null: false, default: {}
      t.string :input_digest, null: false
      t.timestamps
    end

    add_index :recording_studio_agents_tasks, %i[root_recording_id task_key], unique: true,
              name: "index_rsa_tasks_on_root_and_key"

    create_table :recording_studio_agents_agent_runs do |t|
      t.references :task, null: false, foreign_key: { to_table: :recording_studio_agents_tasks },
                          index: { name: "index_rsa_runs_on_task_id" }
      t.column :root_recording_id, recording_id_type, null: false
      t.column :context_recording_id, recording_id_type
      t.string :agent_key, null: false
      t.integer :agent_version, null: false
      t.string :program_digest, null: false
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "pending"
      t.bigint :recording_studio_ai_run_id # no FK: AI history cleanup can delete the row
      t.string :initiator_type, null: false
      t.string :initiator_id, null: false
      t.string :initiator_kind, null: false
      t.string :executor_type
      t.string :executor_id
      t.string :execution_source, null: false
      t.string :lease_token
      t.datetime :lease_expires_at
      t.string :handoff_agent_key
      t.integer :handoff_agent_version
      t.string :failure_category
      t.string :failure_code
      t.text :failure_message
      t.boolean :failure_retryable
      t.string :output_digest
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :recording_studio_agents_agent_runs,
              %i[root_recording_id agent_key agent_version idempotency_key],
              unique: true,
              name: "index_rsa_runs_on_root_agent_idempotency"
    add_index :recording_studio_agents_agent_runs, :recording_studio_ai_run_id,
              unique: true,
              where: "recording_studio_ai_run_id IS NOT NULL",
              name: "index_rsa_runs_on_ai_run_id"
    add_index :recording_studio_agents_agent_runs, :status, name: "index_rsa_runs_on_status"
    add_index :recording_studio_agents_agent_runs, :root_recording_id, name: "index_rsa_runs_on_root"

    create_table :recording_studio_agents_run_activities do |t|
      t.references :agent_run, null: false, foreign_key: { to_table: :recording_studio_agents_agent_runs },
                               index: false
      t.integer :sequence, null: false
      t.string :kind, null: false
      t.json :data, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :recording_studio_agents_run_activities, %i[agent_run_id sequence], unique: true,
              name: "index_rsa_activities_on_run_and_sequence"

    create_table :recording_studio_agents_evaluations do |t|
      t.references :agent_run, null: false, foreign_key: { to_table: :recording_studio_agents_agent_runs },
                               index: false
      t.string :evaluator_type
      t.string :evaluator_id
      t.string :evaluator_key, null: false
      t.integer :evaluator_version, null: false
      t.string :idempotency_key, null: false
      t.string :verdict, null: false
      t.decimal :score, precision: 4, scale: 3
      t.text :notes
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :recording_studio_agents_evaluations,
              %i[agent_run_id evaluator_key evaluator_version idempotency_key],
              unique: true,
              name: "index_rsa_evaluations_on_run_evaluator_idempotency"
  end

  private

  def recording_identifier_type
    if table_exists?(:recording_studio_recordings)
      connection.columns(:recording_studio_recordings).find { |column| column.name == "id" }.type
    else
      :uuid
    end
  end
end
