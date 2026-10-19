# frozen_string_literal: true

require "recording_studio_agents/idempotency_root_backfill"

class ScopeAgentsIdempotencyKeysToRoot < ActiveRecord::Migration[8.1]
  include RecordingStudioAgents::IdempotencyRootBackfill
  include RecordingStudioAgents::IdempotencyRootTrigger

  disable_ddl_transaction!

  BINDING_INDEX = "index_rs_agents_bindings_on_root_and_create_key"
  ITEM_INDEX = "index_rs_agents_items_on_root_and_idempotency_key"
  BINDING_COLUMNS = %i[root_recording_id create_idempotency_key].freeze
  ITEM_COLUMNS = %i[root_recording_id idempotency_key].freeze
  ITEM_WHERE = "idempotency_key IS NOT NULL"
  FILL_FUNCTION = "rs_agents_fill_root_recording_id"
  BINDING_TRIGGER = "rs_agents_bindings_fill_root"
  ITEM_TRIGGER = "rs_agents_items_fill_root"

  def up
    with_lock_timeout do
      add_root_column(:recording_studio_agents_bindings)
      add_root_column(:recording_studio_agents_items)
      install_root_fill_trigger(FILL_FUNCTION, BINDING_TRIGGER, ITEM_TRIGGER)
      backfill(:recording_studio_agents_bindings)
      backfill(:recording_studio_agents_items)
      add_binding_index
      add_item_index
    end
  end

  def down
    with_lock_timeout do
      drop_new_index(BINDING_INDEX)
      drop_new_index(ITEM_INDEX)
      drop_root_fill_trigger(FILL_FUNCTION, BINDING_TRIGGER, ITEM_TRIGGER)
      remove_root(:recording_studio_agents_bindings)
      remove_root(:recording_studio_agents_items)
    end
  end

  private

  def add_root_column(table_name)
    add_column table_name, :root_recording_id, :uuid, if_not_exists: true
    add_foreign_key table_name, :recording_studio_recordings,
                    column: :root_recording_id, validate: false, if_not_exists: true
  end

  def add_binding_index
    drop_invalid_index(BINDING_INDEX)
    add_index :recording_studio_agents_bindings, BINDING_COLUMNS,
              unique: true, name: BINDING_INDEX, algorithm: :concurrently, if_not_exists: true
  end

  def add_item_index
    drop_invalid_index(ITEM_INDEX)
    add_index :recording_studio_agents_items, ITEM_COLUMNS,
              unique: true, where: ITEM_WHERE, name: ITEM_INDEX, algorithm: :concurrently, if_not_exists: true
  end

  def drop_invalid_index(name)
    return unless invalid_index?(name)

    execute "DROP INDEX CONCURRENTLY IF EXISTS #{quote_table_name(name)}"
  end

  def drop_new_index(name)
    execute "DROP INDEX CONCURRENTLY IF EXISTS #{quote_table_name(name)}"
  end

  def invalid_index?(name)
    select_value(<<~SQL.squish) == false
      SELECT i.indisvalid
      FROM pg_index i
      INNER JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = #{quote(name)}
    SQL
  end

  def remove_root(table_name)
    if foreign_key_exists?(table_name, :recording_studio_recordings, column: :root_recording_id)
      remove_foreign_key table_name, column: :root_recording_id
    end
    return unless column_exists?(table_name, :root_recording_id)

    remove_column table_name, :root_recording_id
  end
end
