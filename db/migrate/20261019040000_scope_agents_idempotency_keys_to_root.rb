# frozen_string_literal: true

class ScopeAgentsIdempotencyKeysToRoot < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BINDING_INDEX = "index_rs_agents_bindings_on_root_and_create_key"
  ITEM_INDEX = "index_rs_agents_items_on_root_and_idempotency_key"
  BINDING_COLUMNS = %i[root_recording_id create_idempotency_key].freeze
  ITEM_COLUMNS = %i[root_recording_id idempotency_key].freeze
  ITEM_WHERE = "idempotency_key IS NOT NULL"
  BATCH_SIZE = 1000

  def up
    add_root_column(:recording_studio_agents_bindings)
    add_root_column(:recording_studio_agents_items)
    backfill(:recording_studio_agents_bindings)
    backfill(:recording_studio_agents_items)
    add_binding_index
    add_item_index
  end

  def down
    drop_new_index(BINDING_INDEX)
    drop_new_index(ITEM_INDEX)
    remove_root(:recording_studio_agents_bindings)
    remove_root(:recording_studio_agents_items)
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

  def backfill(table_name)
    loop do
      ids = pending_ids(table_name)
      break if ids.empty?

      copy_roots(table_name, ids)
    end
  end

  def pending_ids(table_name)
    select_values(<<~SQL.squish)
      SELECT id FROM #{quote_table_name(table_name)}
      WHERE root_recording_id IS NULL
      LIMIT #{BATCH_SIZE}
    SQL
  end

  def copy_roots(table_name, ids)
    quoted_ids = ids.map { |id| quote(id) }.join(", ")
    execute <<~SQL.squish
      UPDATE #{quote_table_name(table_name)}
      SET root_recording_id = (
        SELECT recordings.root_recording_id
        FROM recording_studio_recordings AS recordings
        WHERE recordings.id = #{quote_table_name(table_name)}.recording_id
      )
      WHERE id IN (#{quoted_ids})
    SQL
  end
end
