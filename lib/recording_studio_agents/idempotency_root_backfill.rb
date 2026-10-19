# frozen_string_literal: true

module RecordingStudioAgents
  module IdempotencyRootBackfill
    BATCH_SIZE = 1000

    def with_lock_timeout
      execute "SET lock_timeout = '5s'"
      yield
    ensure
      execute "RESET lock_timeout"
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
      sample = null_root_ids(table_name)
      return if sample.empty?

      raise ActiveRecord::MigrationError, null_root_message(table_name, sample)
    end

    def null_root_ids(table_name)
      select_values(<<~SQL.squish)
        SELECT id FROM #{quote_table_name(table_name)}
        WHERE root_recording_id IS NULL
        ORDER BY id
        LIMIT 20
      SQL
    end

    def null_root_message(table_name, sample)
      count = null_root_count(table_name)
      "#{table_name} has #{count} #{'row'.pluralize(count)} with a NULL root_recording_id " \
        "after backfill: #{sample.join(', ')}"
    end

    def null_root_count(table_name)
      select_value(<<~SQL.squish).to_i
        SELECT COUNT(*) FROM #{quote_table_name(table_name)} WHERE root_recording_id IS NULL
      SQL
    end
  end

  module IdempotencyRootTrigger
    def install_root_fill_trigger(function_name, binding_trigger, item_trigger)
      execute fill_function_sql(function_name)
      install_trigger(:recording_studio_agents_bindings, binding_trigger, function_name)
      install_trigger(:recording_studio_agents_items, item_trigger, function_name)
    end

    def install_trigger(table_name, trigger_name, function_name)
      execute <<~SQL.squish
        CREATE OR REPLACE TRIGGER #{quote_table_name(trigger_name)}
        BEFORE INSERT ON #{quote_table_name(table_name)}
        FOR EACH ROW
        EXECUTE FUNCTION #{quote_table_name(function_name)}()
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
end
