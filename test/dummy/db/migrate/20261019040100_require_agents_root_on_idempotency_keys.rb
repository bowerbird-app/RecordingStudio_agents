# frozen_string_literal: true

require "recording_studio_agents/idempotency_root_backfill"

class RequireAgentsRootOnIdempotencyKeys < ActiveRecord::Migration[8.1]
  include RecordingStudioAgents::IdempotencyRootBackfill

  disable_ddl_transaction!

  BINDING_CHECK = "rs_agents_bindings_root_present"
  ITEM_CHECK = "rs_agents_items_root_present"
  OLD_BINDING_INDEX = "index_rs_agents_bindings_on_create_key"
  OLD_ITEM_INDEX = "index_rs_agents_items_on_idempotency_key"
  NEW_BINDING_INDEX = "index_rs_agents_bindings_on_root_and_create_key"
  NEW_ITEM_INDEX = "index_rs_agents_items_on_root_and_idempotency_key"
  IRREVERSIBLE = "Cannot restore the global idempotency unique indexes once the same key exists in two workspaces"

  def up
    with_lock_timeout do
      backfill(:recording_studio_agents_bindings)
      backfill(:recording_studio_agents_items)
      validate_root_keys
      require_root(:recording_studio_agents_bindings, BINDING_CHECK)
      require_root(:recording_studio_agents_items, ITEM_CHECK)
      ensure_replacement_indexes!
      drop_old_index(:recording_studio_agents_bindings, OLD_BINDING_INDEX)
      drop_old_index(:recording_studio_agents_items, OLD_ITEM_INDEX)
    end
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
