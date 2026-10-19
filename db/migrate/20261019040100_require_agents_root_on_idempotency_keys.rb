# frozen_string_literal: true

class RequireAgentsRootOnIdempotencyKeys < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    backfill(:recording_studio_agents_bindings)
    backfill(:recording_studio_agents_items)
    require_root(:recording_studio_agents_bindings)
    require_root(:recording_studio_agents_items)
  end

  def down
    relax_root(:recording_studio_agents_bindings)
    relax_root(:recording_studio_agents_items)
  end

  private

  def require_root(table_name)
    change_column_null table_name, :root_recording_id, false
  end

  def relax_root(table_name)
    change_column_null table_name, :root_recording_id, true
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
