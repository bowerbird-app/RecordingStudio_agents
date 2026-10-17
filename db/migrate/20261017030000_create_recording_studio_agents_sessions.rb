# frozen_string_literal: true

class CreateRecordingStudioAgentsSessions < ActiveRecord::Migration[8.1]
  def change
    create_sessions
    create_bindings
    add_binding_indexes
    create_items
    add_item_indexes
  end

  private

  def create_sessions
    create_table :recording_studio_agents_sessions, id: :uuid do |t|
      t.string :title
      t.string :status, null: false
      t.string :model, null: false
      t.string :profile
      t.string :purpose
      t.datetime :created_at, null: false
    end
  end

  def create_bindings
    create_table :recording_studio_agents_bindings, id: :uuid do |table|
      binding_columns(table)
    end
  end

  def binding_columns(table)
    table.references :recording, type: :uuid, null: false,
                                 foreign_key: { to_table: :recording_studio_recordings },
                                 index: { unique: true }
    table.string :provider, null: false
    table.string :provider_session_id
    table.string :preview
    table.string :create_idempotency_key, null: false
    binding_times(table)
  end

  def binding_times(table)
    table.datetime :last_activity_at, null: false
    table.datetime :expires_at, null: false
    table.timestamps
  end

  def add_binding_indexes
    add_index :recording_studio_agents_bindings, :provider_session_id,
              unique: true, where: "provider_session_id IS NOT NULL",
              name: "index_rs_agents_bindings_on_provider_session"
    add_index :recording_studio_agents_bindings, :create_idempotency_key,
              unique: true, name: "index_rs_agents_bindings_on_create_key"
    add_index :recording_studio_agents_bindings, :expires_at
  end

  def create_items
    create_table :recording_studio_agents_items, id: :string do |t|
      t.uuid :recording_id, null: false
      t.string :provider_item_id
      t.string :role, null: false
      t.text :text, null: false
      t.string :status, null: false, default: "done"
      t.string :idempotency_key
      t.datetime :created_at, null: false
    end
  end

  def add_item_indexes
    add_index :recording_studio_agents_items, :recording_id
    add_index :recording_studio_agents_items, :idempotency_key,
              unique: true, where: "idempotency_key IS NOT NULL",
              name: "index_rs_agents_items_on_idempotency_key"
    add_foreign_key :recording_studio_agents_items, :recording_studio_recordings, column: :recording_id
  end
end
