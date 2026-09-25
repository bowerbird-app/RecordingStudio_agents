# frozen_string_literal: true

class CreateRecordingStudioWebSearchRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_web_search_runs, id: :uuid do |t|
      t.string :provider, null: false
      t.string :query, null: false
      t.string :status, null: false
      t.string :outcome, null: false
      t.integer :result_count
      t.integer :duration_ms
      t.decimal :estimated_cost_usd, precision: 12, scale: 6, null: false, default: 0
      t.jsonb :parameters, null: false, default: {}
      t.timestamps
    end

    add_index :recording_studio_web_search_runs, :created_at
    add_index :recording_studio_web_search_runs, :provider
    add_index :recording_studio_web_search_runs, :status
  end
end
