# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261019040000_scope_agents_idempotency_keys_to_root")
require Rails.root.join("db/migrate/20261019040100_require_agents_root_on_idempotency_keys")

class IdempotencyMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  SCRATCH = "agents_idempotency_migration"
  BINDING_INDEX = "index_rs_agents_bindings_on_root_and_create_key"
  ITEM_INDEX = "index_rs_agents_items_on_root_and_idempotency_key"
  OLD_BINDING_INDEX = "index_rs_agents_bindings_on_create_key"
  OLD_ITEM_INDEX = "index_rs_agents_items_on_idempotency_key"

  setup do
    @original = ActiveRecord::Base.connection_db_config
    create_scratch_database
  end

  teardown do
    drop_scratch_database
  end

  test "A backfills and can be re-run, then B requires the root and drops the global indexes" do
    pid = fork do
      run_forked_migration
    rescue StandardError => e
      warn "#{e.class}: #{e.message}"
      warn e.backtrace.first(20).join("\n")
      exit! 1
    end
    _, status = Process.wait2(pid)
    assert_predicate status, :success?
  end

  def run_forked_migration
    ActiveRecord::Base.connection_pool.disconnect!
    ActiveRecord::Base.establish_connection(scratch_config)
    load_pre_migration_schema
    @alpha, @zulu, @alpha_chat, @zulu_chat = seed_workspaces
    @null_binding = insert_binding(@alpha_chat, "null-root-key")
    insert_item(@alpha_chat, "item-alpha", "alpha-item")
    insert_item(@zulu_chat, "item-zulu", "zulu-item")
    insert_binding(@zulu_chat, "zulu-key")
    exercise_migrations
    ActiveRecord::Base.connection_pool.disconnect!
    exit! 0
  end

  def exercise_migrations
    simulate_partial_failure
    assert_nil root_of("recording_studio_agents_bindings", @null_binding)

    migrate_a
    assert_backfilled
    assert_old_indexes
    assert_new_indexes(valid: true)
    refute root_foreign_key_validated?("recording_studio_agents_bindings")

    migrate_a
    assert_backfilled

    straggler = insert_binding(@zulu_chat, "straggler-key", include_root: true, root: nil)
    migrate_b

    assert_equal @zulu, root_of("recording_studio_agents_bindings", straggler)
    assert_not_null("recording_studio_agents_bindings")
    assert_not_null("recording_studio_agents_items")
    assert root_foreign_key_validated?("recording_studio_agents_bindings")
    assert root_foreign_key_validated?("recording_studio_agents_items")
    refute index_exists?(OLD_BINDING_INDEX)
    refute index_exists?(OLD_ITEM_INDEX)
    refute check_exists?("rs_agents_bindings_root_present")
    refute check_exists?("rs_agents_items_root_present")
    assert_per_root_uniqueness
  end

  private

  def simulate_partial_failure
    connection.add_column :recording_studio_agents_bindings, :root_recording_id, :uuid
    connection.add_column :recording_studio_agents_items, :root_recording_id, :uuid
    connection.execute(<<~SQL.squish)
      CREATE INDEX #{BINDING_INDEX}
      ON recording_studio_agents_bindings (root_recording_id, create_idempotency_key)
    SQL
    connection.execute(<<~SQL.squish)
      UPDATE pg_index SET indisvalid = false
      WHERE indexrelid = #{connection.quote(BINDING_INDEX)}::regclass
    SQL
  end

  def migrate_a
    ScopeAgentsIdempotencyKeysToRoot.new.exec_migration(connection, :up)
  end

  def migrate_b
    RequireAgentsRootOnIdempotencyKeys.new.exec_migration(connection, :up)
  end

  def assert_backfilled
    assert_equal @alpha, root_of("recording_studio_agents_bindings", @null_binding)
    assert_equal @alpha, item_root("item-alpha")
    assert_equal @zulu, item_root("item-zulu")
  end

  def assert_old_indexes
    assert index_exists?(OLD_BINDING_INDEX)
    assert index_exists?(OLD_ITEM_INDEX)
  end

  def assert_new_indexes(valid:)
    assert_equal valid, index_valid?(BINDING_INDEX)
    assert_equal valid, index_valid?(ITEM_INDEX)
  end

  def assert_per_root_uniqueness
    insert_binding(@zulu_chat, "shared-key", include_root: true, root: @zulu)
    insert_binding(@alpha_chat, "shared-key", include_root: true, root: @alpha)
    error = assert_raises(ActiveRecord::StatementInvalid) do
      insert_binding(@alpha_chat, "shared-key", include_root: true, root: @alpha)
    end
    assert_match(/unique|duplicate/i, error.message)
  end

  def assert_not_null(table_name)
    column = connection.columns(table_name).find { |entry| entry.name == "root_recording_id" }
    assert_equal false, column.null
  end

  def seed_workspaces
    alpha = insert_recording(nil)
    zulu = insert_recording(nil)
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_recordings
      SET root_recording_id = id
      WHERE id IN (#{connection.quote(alpha)}, #{connection.quote(zulu)})
    SQL
    [alpha, zulu, insert_recording(alpha), insert_recording(zulu)]
  end

  def insert_recording(root_id)
    id = SecureRandom.uuid
    connection.execute(<<~SQL.squish)
      INSERT INTO recording_studio_recordings (id, root_recording_id)
      VALUES (#{connection.quote(id)}, #{connection.quote(root_id)})
    SQL
    id
  end

  def insert_binding(recording_id, key, include_root: false, root: nil)
    id = SecureRandom.uuid
    root_sql = include_root ? ", root_recording_id" : ""
    root_value = include_root ? ", #{connection.quote(root)}" : ""
    now = connection.quote(Time.current)
    connection.execute(<<~SQL.squish)
      INSERT INTO recording_studio_agents_bindings (
        id, recording_id, provider, create_idempotency_key, last_activity_at, expires_at, created_at, updated_at#{root_sql}
      ) VALUES (
        #{connection.quote(id)}, #{connection.quote(recording_id)}, 'openai', #{connection.quote(key)},
        #{now}, #{now}, #{now}, #{now}#{root_value}
      )
    SQL
    id
  end

  def insert_item(recording_id, id, key)
    connection.execute(<<~SQL.squish)
      INSERT INTO recording_studio_agents_items (
        id, recording_id, role, text, status, idempotency_key, created_at
      ) VALUES (
        #{connection.quote(id)}, #{connection.quote(recording_id)}, 'user', 'hello', 'done',
        #{connection.quote(key)}, #{connection.quote(Time.current)}
      )
    SQL
  end

  def load_pre_migration_schema
    connection.execute(<<~SQL)
      CREATE TABLE recording_studio_recordings (
        id uuid PRIMARY KEY,
        root_recording_id uuid
      );
      CREATE TABLE recording_studio_agents_bindings (
        id uuid PRIMARY KEY,
        recording_id uuid NOT NULL REFERENCES recording_studio_recordings (id),
        provider varchar NOT NULL,
        provider_session_id varchar,
        preview varchar,
        create_idempotency_key varchar NOT NULL,
        last_activity_at timestamp NOT NULL,
        expires_at timestamp NOT NULL,
        created_at timestamp NOT NULL,
        updated_at timestamp NOT NULL
      );
      CREATE UNIQUE INDEX #{OLD_BINDING_INDEX}
        ON recording_studio_agents_bindings (create_idempotency_key);
      CREATE TABLE recording_studio_agents_items (
        id varchar PRIMARY KEY,
        recording_id uuid NOT NULL REFERENCES recording_studio_recordings (id),
        provider_item_id varchar,
        role varchar NOT NULL,
        text text NOT NULL,
        status varchar NOT NULL DEFAULT 'done',
        idempotency_key varchar,
        created_at timestamp NOT NULL
      );
      CREATE UNIQUE INDEX #{OLD_ITEM_INDEX}
        ON recording_studio_agents_items (idempotency_key)
        WHERE idempotency_key IS NOT NULL;
    SQL
  end

  def root_of(table_name, id)
    connection.select_value(<<~SQL.squish)
      SELECT root_recording_id FROM #{table_name} WHERE id = #{connection.quote(id)}
    SQL
  end

  def item_root(id)
    root_of("recording_studio_agents_items", id)
  end

  def index_exists?(name)
    !index_valid?(name).nil?
  end

  def index_valid?(name)
    connection.select_value(<<~SQL.squish)
      SELECT i.indisvalid
      FROM pg_index i
      INNER JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = #{connection.quote(name)}
    SQL
  end

  def root_foreign_key_validated?(table_name)
    connection.select_value(<<~SQL.squish) == true
      SELECT c.convalidated
      FROM pg_constraint c
      INNER JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
      WHERE c.conrelid = #{connection.quote(table_name)}::regclass
        AND c.contype = 'f'
        AND a.attname = 'root_recording_id'
    SQL
  end

  def check_exists?(name)
    connection.select_value(<<~SQL.squish).present?
      SELECT 1 FROM pg_constraint WHERE conname = #{connection.quote(name)}
    SQL
  end

  def create_scratch_database
    terminate_scratch
    admin.execute("DROP DATABASE IF EXISTS #{SCRATCH}")
    admin.execute("CREATE DATABASE #{SCRATCH}")
  end

  def drop_scratch_database
    terminate_scratch
    admin.execute("DROP DATABASE IF EXISTS #{SCRATCH}")
  end

  def terminate_scratch
    admin.execute(<<~SQL.squish)
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = #{admin.quote(SCRATCH)} AND pid <> pg_backend_pid()
    SQL
  end

  def scratch_config
    @original.configuration_hash.merge(database: SCRATCH)
  end

  def admin
    ActiveRecord::Base.connection
  end

  def connection
    ActiveRecord::Base.connection
  end
end
