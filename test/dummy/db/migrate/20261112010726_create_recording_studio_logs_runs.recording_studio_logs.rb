# frozen_string_literal: true

# This migration comes from recording_studio_logs (originally 20261015000001)
class CreateRecordingStudioLogsRuns < ActiveRecord::Migration[8.1]
  def change
    aggregation_runs
    maintenance_runs
  end

  def aggregation_runs
    create_table :recording_studio_logs_aggregation_runs, id: :uuid do |table|
      table.string :aggregation_name, null: false
      table.date :day, null: false
      table.string :status, null: false
      table.text :error_message
      table.datetime :finished_at
      table.timestamps
    end
    index_aggregation_runs
  end

  def maintenance_runs
    create_table :recording_studio_logs_maintenance_runs, id: :uuid do |table|
      table.string :task, null: false
      table.string :subject, null: false
      table.string :status, null: false
      table.text :details
      table.datetime :finished_at, null: false
      table.timestamps
    end
    index_maintenance_runs
  end

  private

  def index_aggregation_runs
    add_index :recording_studio_logs_aggregation_runs, %i[aggregation_name day],
              unique: true, name: "index_rs_logs_aggregation_runs_on_name_and_day"
  end

  def index_maintenance_runs
    add_index :recording_studio_logs_maintenance_runs, %i[task subject finished_at],
              name: "index_rs_logs_maintenance_runs_on_task_and_subject"
  end
end
