# frozen_string_literal: true

# rubocop:disable Style/OneClassPerFile -- the generator copies this file alone, so the SQL stays inside it.

# Copied into this migration so a later gem change cannot alter a migration that already shipped.
module RequireAgentsRootOnIdempotencySupport
  BATCH_SIZE = 1000

  def with_lock_timeout
    previous = select_value("SHOW lock_timeout")
    execute "SET lock_timeout = '5s'"
    yield
  ensure
    restore_lock_timeout(previous)
  end

  def restore_lock_timeout(previous)
    return if previous.nil?

    execute "SET lock_timeout = #{quote(previous)}"
  end

  def backfill(table_name)
    walk_null_roots(table_name)
    raise_if_roots_missing(table_name)
  end

  def walk_null_roots(table_name)
    last_id = nil
    loop do
      ids = pending_ids(table_name, last_id)
      break if ids.empty?

      copy_roots(table_name, ids)
      last_id = ids.last
    end
  end

  def pending_ids(table_name, last_id)
    select_values(<<~SQL.squish)
      SELECT id FROM #{quote_table_name(table_name)}
      WHERE root_recording_id IS NULL #{id_cursor(last_id)}
      ORDER BY id
      LIMIT #{BATCH_SIZE}
    SQL
  end

  def id_cursor(last_id)
    return if last_id.nil?

    "AND id > #{quote(last_id)}"
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

  def raise_if_roots_missing(table_name)
    rows = null_root_rows(table_name)
    return if rows.empty?

    raise ActiveRecord::MigrationError, null_root_message(table_name, rows)
  end

  def null_root_rows(table_name)
    select_all(<<~SQL.squish).to_a
      SELECT id, recording_id FROM #{quote_table_name(table_name)}
      WHERE root_recording_id IS NULL
      ORDER BY id
      LIMIT 20
    SQL
  end

  def null_root_message(table_name, rows)
    count = null_root_count(table_name)
    recordings = rows.map { |row| row["recording_id"] }.uniq.join(", ")
    "#{table_name} has #{count} #{'row'.pluralize(count)} with a NULL root_recording_id after backfill. " \
      "Recordings missing a root: #{recordings}. " \
      "Set recording_studio_recordings.root_recording_id for those recordings, then re-run this migration."
  end

  def null_root_count(table_name)
    select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM #{quote_table_name(table_name)} WHERE root_recording_id IS NULL
    SQL
  end
end

class RequireAgentsRootOnIdempotencyKeys < ActiveRecord::Migration[8.1]
  include RequireAgentsRootOnIdempotencySupport

  disable_ddl_transaction!

  BINDING_CHECK = "rs_agents_bindings_root_present"
  ITEM_CHECK = "rs_agents_items_root_present"
  OLD_BINDING_INDEX = "index_rs_agents_bindings_on_create_key"
  OLD_ITEM_INDEX = "index_rs_agents_items_on_idempotency_key"
  NEW_BINDING_INDEX = "index_rs_agents_bindings_on_root_and_create_key"
  NEW_ITEM_INDEX = "index_rs_agents_items_on_root_and_idempotency_key"
  IRREVERSIBLE = "Cannot restore the global idempotency unique indexes once the same key exists in two workspaces"

  def up
    with_lock_timeout { require_roots }
    drop_old_index(:recording_studio_agents_bindings, OLD_BINDING_INDEX)
    drop_old_index(:recording_studio_agents_items, OLD_ITEM_INDEX)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, IRREVERSIBLE
  end

  private

  def require_roots
    backfill(:recording_studio_agents_bindings)
    backfill(:recording_studio_agents_items)
    validate_root_keys
    require_root(:recording_studio_agents_bindings, BINDING_CHECK)
    require_root(:recording_studio_agents_items, ITEM_CHECK)
    ensure_replacement_indexes!
  end

  def validate_root_keys
    validate_foreign_key :recording_studio_agents_bindings, column: :root_recording_id
    validate_foreign_key :recording_studio_agents_items, column: :root_recording_id
  end

  def require_root(table_name, check_name)
    add_check_constraint table_name, "root_recording_id IS NOT NULL",
                         name: check_name, validate: false, if_not_exists: true
    validate_constraint table_name, check_name
    change_column_null table_name, :root_recording_id, false
    remove_check_constraint table_name, name: check_name, if_exists: true
  end

  def ensure_replacement_indexes!
    assert_index_valid!(NEW_BINDING_INDEX)
    assert_index_valid!(NEW_ITEM_INDEX)
  end

  def assert_index_valid!(name)
    return if index_valid?(name)

    raise ActiveRecord::MigrationError, "#{name} is not a valid index, so the old global unique index stays"
  end

  def index_valid?(name)
    select_value(<<~SQL.squish) == true
      SELECT i.indisvalid
      FROM pg_index i
      INNER JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = #{quote(name)}
    SQL
  end

  def drop_old_index(table_name, name)
    remove_index table_name, name: name, algorithm: :concurrently, if_exists: true
  end
end
# rubocop:enable Style/OneClassPerFile
