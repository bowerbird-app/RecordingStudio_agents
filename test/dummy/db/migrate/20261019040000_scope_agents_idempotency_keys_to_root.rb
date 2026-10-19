# frozen_string_literal: true

class ScopeAgentsIdempotencyKeysToRoot < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BINDING_INDEX = "index_rs_agents_bindings_on_root_and_create_key"
  ITEM_INDEX = "index_rs_agents_items_on_root_and_idempotency_key"
  OLD_BINDING_INDEX = "index_rs_agents_bindings_on_create_key"
  OLD_ITEM_INDEX = "index_rs_agents_items_on_idempotency_key"
  BINDING_COLUMNS = %i[root_recording_id create_idempotency_key].freeze
  ITEM_COLUMNS = %i[root_recording_id idempotency_key].freeze
  ITEM_WHERE = "idempotency_key IS NOT NULL"
  ROOT_FOREIGN_KEY = { to_table: :recording_studio_recordings }.freeze
  IRREVERSIBLE = "Cannot restore the global idempotency unique indexes once the same key exists in two workspaces"

  def up
    add_root_column(:recording_studio_agents_bindings)
    add_root_column(:recording_studio_agents_items)
    backfill(:recording_studio_agents_bindings)
    backfill(:recording_studio_agents_items)
    add_root_indexes
    remove_global_indexes
  end

  def down
    raise ActiveRecord::IrreversibleMigration, IRREVERSIBLE
  end

  private

  def add_root_indexes
    add_index :recording_studio_agents_bindings, BINDING_COLUMNS,
              unique: true, name: BINDING_INDEX, algorithm: :concurrently
    add_index :recording_studio_agents_items, ITEM_COLUMNS,
              unique: true, where: ITEM_WHERE, name: ITEM_INDEX, algorithm: :concurrently
  end

  def remove_global_indexes
    remove_index :recording_studio_agents_bindings, name: OLD_BINDING_INDEX, algorithm: :concurrently
    remove_index :recording_studio_agents_items, name: OLD_ITEM_INDEX, algorithm: :concurrently
  end

  def add_root_column(table_name)
    add_reference table_name, :root_recording, type: :uuid, index: false, foreign_key: ROOT_FOREIGN_KEY
  end

  def backfill(table_name)
    rows_for(table_name).where(root_recording_id: nil).in_batches do |batch|
      batch.update_all(root_copy_sql(table_name))
    end
  end

  def rows_for(table_name)
    Class.new(ActiveRecord::Base) { self.table_name = table_name }
  end

  def root_copy_sql(table_name)
    <<~SQL.squish
      root_recording_id = (
        SELECT recordings.root_recording_id
        FROM recording_studio_recordings AS recordings
        WHERE recordings.id = #{table_name}.recording_id
      )
    SQL
  end
end
