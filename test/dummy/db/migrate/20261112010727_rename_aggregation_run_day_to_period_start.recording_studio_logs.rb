# frozen_string_literal: true

# This migration comes from recording_studio_logs (originally 20261021000001)
class RenameAggregationRunDayToPeriodStart < ActiveRecord::Migration[8.1]
  def up
    RecordingStudioLogs::Schema.upgrade_aggregation_runs!(connection)
  end

  def down
    RecordingStudioLogs::Schema.downgrade_aggregation_runs!(connection)
  end
end
