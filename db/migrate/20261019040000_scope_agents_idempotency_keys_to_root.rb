# frozen_string_literal: true

# rubocop:disable Style/OneClassPerFile -- the generator copies this file alone, so the SQL stays inside it.

# Copied into this migration so a later gem change cannot alter a migration that already shipped.
module ScopeAgentsIdempotencySupport
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

module ScopeAgentsIdempotencyTrigger
  def install_root_fill_trigger(function_name, binding_trigger, item_trigger)
    execute fill_function_sql(function_name)
    install_trigger(:recording_studio_agents_bindings, binding_trigger, function_name)
    install_trigger(:recording_studio_agents_items, item_trigger, function_name)
  end

  def install_trigger(table_name, trigger_name, function_name)
    drop_fill_trigger(table_name, trigger_name)
    execute <<~SQL.squish
      CREATE TRIGGER #{quote_table_name(trigger_name)}
      BEFORE INSERT ON #{quote_table_name(table_name)}
      FOR EACH ROW
      EXECUTE PROCEDURE #{quote_table_name(function_name)}()
    SQL
  end

  def fill_function_sql(function_name)
    <<~SQL
      CREATE OR REPLACE FUNCTION #{quote_table_name(function_name)}()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.root_recording_id IS NULL THEN
          SELECT recordings.root_recording_id INTO NEW.root_recording_id
          FROM recording_studio_recordings AS recordings
          WHERE recordings.id = NEW.recording_id;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end

  def drop_root_fill_trigger(function_name, binding_trigger, item_trigger)
    drop_fill_trigger(:recording_studio_agents_bindings, binding_trigger)
    drop_fill_trigger(:recording_studio_agents_items, item_trigger)
    execute "DROP FUNCTION IF EXISTS #{quote_table_name(function_name)}()"
  end

  def drop_fill_trigger(table_name, trigger_name)
    execute "DROP TRIGGER IF EXISTS #{quote_table_name(trigger_name)} ON #{quote_table_name(table_name)}"
  end
end

class ScopeAgentsIdempotencyKeysToRoot < ActiveRecord::Migration[8.1]
  include ScopeAgentsIdempotencySupport
  include ScopeAgentsIdempotencyTrigger

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
    with_lock_timeout { add_roots_and_backfill }
    add_binding_index
    add_item_index
  end

  def down
    drop_new_index(BINDING_INDEX)
    drop_new_index(ITEM_INDEX)
    with_lock_timeout { drop_roots }
  end

  private

  def add_roots_and_backfill
    add_root_column(:recording_studio_agents_bindings)
    add_root_column(:recording_studio_agents_items)
    install_root_fill_trigger(FILL_FUNCTION, BINDING_TRIGGER, ITEM_TRIGGER)
    backfill(:recording_studio_agents_bindings)
    backfill(:recording_studio_agents_items)
  end

  def drop_roots
    drop_root_fill_trigger(FILL_FUNCTION, BINDING_TRIGGER, ITEM_TRIGGER)
    remove_root(:recording_studio_agents_bindings)
    remove_root(:recording_studio_agents_items)
  end

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
# rubocop:enable Style/OneClassPerFile
