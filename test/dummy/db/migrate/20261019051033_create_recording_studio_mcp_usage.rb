# frozen_string_literal: true

class CreateRecordingStudioMcpUsage < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_mcp_usage_logs, id: :uuid do |t|
      t.datetime :occurred_at, null: false
      t.string :method_name, null: false
      t.string :subject_name, null: false, default: ""
      t.integer :status_code, null: false
      t.integer :duration_ms, null: false
      t.boolean :rate_limited, null: false, default: false
      t.boolean :failed, null: false, default: false
      t.uuid :api_client_id

      t.timestamps
    end

    add_index :recording_studio_mcp_usage_logs, :occurred_at
    add_index :recording_studio_mcp_usage_logs, %i[api_client_id occurred_at],
              name: "index_rs_mcp_usage_logs_on_client_and_time"

    create_table :recording_studio_mcp_usage_daily_metrics, id: :uuid do |t|
      t.date :metric_date, null: false
      t.string :method_name, null: false
      t.string :subject_name, null: false, default: ""
      t.integer :call_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :rate_limited_count, null: false, default: 0

      t.timestamps
    end

    add_index :recording_studio_mcp_usage_daily_metrics,
              %i[metric_date method_name subject_name],
              unique: true,
              name: "index_rs_mcp_usage_daily_on_day_method_subject"
  end
end
