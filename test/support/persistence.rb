# frozen_string_literal: true

require "active_record"

module PersistenceSupport
  module_function

  def connect!
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Base.connection.create_table :recording_studio_agents_tasks do |t|
      t.string :root_recording_id, null: false
      t.string :context_recording_id
      t.string :task_key, null: false
      t.text :goal, null: false
      t.json :context_json, null: false, default: {}
      t.string :input_digest, null: false
      t.timestamps
    end
    ActiveRecord::Base.connection.add_index(
      :recording_studio_agents_tasks,
      %i[root_recording_id task_key],
      unique: true
    )

    ActiveRecord::Base.connection.create_table :recording_studio_agents_agent_runs do |t|
      t.integer :task_id, null: false
      t.string :root_recording_id, null: false
      t.string :context_recording_id
      t.string :agent_key, null: false
      t.integer :agent_version, null: false
      t.string :program_digest, null: false
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "pending"
      t.integer :recording_studio_ai_run_id
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
    ActiveRecord::Base.connection.add_index(
      :recording_studio_agents_agent_runs,
      %i[root_recording_id agent_key agent_version idempotency_key],
      unique: true
    )

    ActiveRecord::Base.connection.create_table :recording_studio_agents_run_activities do |t|
      t.integer :agent_run_id, null: false
      t.integer :sequence, null: false
      t.string :kind, null: false
      t.json :data, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end
    ActiveRecord::Base.connection.add_index(
      :recording_studio_agents_run_activities,
      %i[agent_run_id sequence],
      unique: true
    )

    ActiveRecord::Base.connection.create_table :recording_studio_agents_evaluations do |t|
      t.integer :agent_run_id, null: false
      t.string :evaluator_type
      t.string :evaluator_id
      t.string :evaluator_key, null: false
      t.integer :evaluator_version, null: false
      t.string :idempotency_key, null: false
      t.string :verdict, null: false
      t.decimal :score
      t.text :notes
      t.json :metadata, null: false, default: {}
      t.timestamps
    end
    ActiveRecord::Base.connection.add_index(
      :recording_studio_agents_evaluations,
      %i[agent_run_id evaluator_key evaluator_version idempotency_key],
      unique: true
    )

    require File.expand_path("../../app/models/recording_studio_agents/application_record.rb", __dir__)
    require File.expand_path("../../app/models/recording_studio_agents/task.rb", __dir__)
    require File.expand_path("../../app/models/recording_studio_agents/agent_run.rb", __dir__)
    require File.expand_path("../../app/models/recording_studio_agents/run_activity.rb", __dir__)
    require File.expand_path("../../app/models/recording_studio_agents/evaluation.rb", __dir__)
  end
end

class PersistenceTestCase < Minitest::Test
  include RegistryHelpers

  TestActor = Struct.new(:id)

  FakeRoot = Struct.new(:id)

  def setup
    super
    PersistenceSupport.connect!
    @previous_authorization_handler = RecordingStudioAI.configuration.authorization_handler
    @previous_attribution_validator = RecordingStudioAI.configuration.attribution_validator
    RecordingStudioAI.configuration.authorization_handler = ->(**) { true }
    RecordingStudioAI.configuration.attribution_validator = ->(**) {}
  end

  def teardown
    RecordingStudioAI.configuration.authorization_handler = @previous_authorization_handler
    RecordingStudioAI.configuration.attribution_validator = @previous_attribution_validator
    super if defined?(super)
  end

  def actor
    TestActor.new(7)
  end

  def root
    FakeRoot.new("root-1")
  end

  def task_input(key: "find_page", goal: "Find Getting Started.")
    RecordingStudioAgents::TaskInput.new(key: key, goal: goal, context: { "title" => "Getting Started" })
  end

  def generation_response(text: "Found Getting Started.", run_id: 41, error: nil)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: text,
      error: error,
      run: Struct.new(:id, :status).new(run_id, error ? "failed" : "completed")
    )
  end
end
