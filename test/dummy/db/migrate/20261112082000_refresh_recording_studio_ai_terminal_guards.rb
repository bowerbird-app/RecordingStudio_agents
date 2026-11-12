# frozen_string_literal: true

# Recording Studio AI 0.20.0 builds rsai_terminal_*_guard before it drops
# correlation_id, and it does not replace the function. An update then raises
# PG::UndefinedColumn. Rebuild the two guards that named that column.
class RefreshRecordingStudioAITerminalGuards < ActiveRecord::Migration[8.1]
  TABLES = {
    recording_studio_ai_runs: %w[completed failed cancelled],
    recording_studio_ai_batches: %w[completed partially_completed failed cancelled expired]
  }.freeze
  MUTABLE = %w[id metadata lock_version created_at updated_at].freeze

  def up
    return unless connection.adapter_name.match?(/PostgreSQL/i)

    TABLES.each { |table, statuses| replace_guard(table, statuses) }
  end

  def down; end

  private

  def replace_guard(table, statuses)
    suffix = table.to_s.delete_prefix("recording_studio_ai_")
    function = "rsai_terminal_#{suffix}_guard"
    trigger = "rsai_terminal_#{suffix}"
    execute "DROP TRIGGER IF EXISTS #{trigger} ON #{table}"
    execute "DROP FUNCTION IF EXISTS #{function}()"
    columns = connection.columns(table).index_by(&:name)
    comparisons = columns.keys.reject { |name| MUTABLE.include?(name) }.map do |name|
      quoted = connection.quote_column_name(name)
      if columns.fetch(name).sql_type == "json"
        "(OLD.#{quoted})::jsonb IS DISTINCT FROM (NEW.#{quoted})::jsonb"
      else
        "OLD.#{quoted} IS DISTINCT FROM NEW.#{quoted}"
      end
    end.join(" OR ")
    quoted_statuses = statuses.map { |status| connection.quote(status) }.join(", ")
    execute <<~SQL
      CREATE FUNCTION #{function}() RETURNS trigger AS $$
      BEGIN
        IF OLD.status IN (#{quoted_statuses}) AND (#{comparisons}) THEN
          RAISE EXCEPTION 'terminal execution history is immutable' USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
    execute <<~SQL
      CREATE TRIGGER #{trigger}
      BEFORE UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION #{function}();
    SQL
  end
end
