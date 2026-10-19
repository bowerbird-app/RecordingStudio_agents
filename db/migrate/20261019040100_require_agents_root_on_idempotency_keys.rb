# frozen_string_literal: true

class RequireAgentsRootOnIdempotencyKeys < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BINDING_CHECK = "rs_agents_bindings_root_present"
  ITEM_CHECK = "rs_agents_items_root_present"
  OLD_BINDING_INDEX = "index_rs_agents_bindings_on_create_key"
  OLD_ITEM_INDEX = "index_rs_agents_items_on_idempotency_key"
  IRREVERSIBLE = "Cannot restore the global idempotency unique indexes once the same key exists in two workspaces"
  BATCH_SIZE = 1000

  def up
    backfill(:recording_studio_agents_bindings)
    backfill(:recording_studio_agents_items)
    validate_root_keys
    require_root(:recording_studio_agents_bindings, BINDING_CHECK)
    require_root(:recording_studio_agents_items, ITEM_CHECK)
    drop_old_index(:recording_studio_agents_bindings, OLD_BINDING_INDEX)
    drop_old_index(:recording_studio_agents_items, OLD_ITEM_INDEX)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, IRREVERSIBLE
  end

  private

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

  def drop_old_index(table_name, name)
    remove_index table_name, name: name, algorithm: :concurrently, if_exists: true
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
