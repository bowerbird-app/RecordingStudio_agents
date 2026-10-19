# frozen_string_literal: true

class ScopeAgentsIdempotencyKeysToRoot < ActiveRecord::Migration[8.1]
  BINDING_INDEX = "index_rs_agents_bindings_on_root_and_create_key"
  ITEM_INDEX = "index_rs_agents_items_on_root_and_idempotency_key"
  OLD_BINDING_INDEX = "index_rs_agents_bindings_on_create_key"
  OLD_ITEM_INDEX = "index_rs_agents_items_on_idempotency_key"
  ROOT_FOREIGN_KEY = { to_table: :recording_studio_recordings }.freeze

  def up
    add_root_column(:recording_studio_agents_bindings)
    add_root_column(:recording_studio_agents_items)
    backfill(:recording_studio_agents_bindings)
    backfill(:recording_studio_agents_items)
    change_column_null :recording_studio_agents_bindings, :root_recording_id, false
    change_column_null :recording_studio_agents_items, :root_recording_id, false
    replace_global_indexes_with_root_indexes
  end

  def down
    remove_index :recording_studio_agents_bindings, name: BINDING_INDEX
    remove_index :recording_studio_agents_items, name: ITEM_INDEX
    add_index :recording_studio_agents_bindings, :create_idempotency_key, unique: true, name: OLD_BINDING_INDEX
    add_index :recording_studio_agents_items, :idempotency_key,
              unique: true, where: "idempotency_key IS NOT NULL", name: OLD_ITEM_INDEX
    remove_root_column(:recording_studio_agents_bindings)
    remove_root_column(:recording_studio_agents_items)
  end

  private

  def replace_global_indexes_with_root_indexes
    remove_index :recording_studio_agents_bindings, name: OLD_BINDING_INDEX
    remove_index :recording_studio_agents_items, name: OLD_ITEM_INDEX
    add_index :recording_studio_agents_bindings, %i[root_recording_id create_idempotency_key],
              unique: true, name: BINDING_INDEX
    add_index :recording_studio_agents_items, %i[root_recording_id idempotency_key],
              unique: true, where: "idempotency_key IS NOT NULL", name: ITEM_INDEX
  end

  def add_root_column(table_name)
    add_reference table_name, :root_recording, type: :uuid, index: false, foreign_key: ROOT_FOREIGN_KEY
  end

  def remove_root_column(table_name)
    remove_reference table_name, :root_recording, type: :uuid, foreign_key: ROOT_FOREIGN_KEY
  end

  def backfill(table_name)
    execute <<~SQL.squish
      UPDATE #{table_name}
      SET root_recording_id = recording_studio_recordings.root_recording_id
      FROM recording_studio_recordings
      WHERE #{table_name}.recording_id = recording_studio_recordings.id
        AND #{table_name}.root_recording_id IS NULL
    SQL
  end
end
