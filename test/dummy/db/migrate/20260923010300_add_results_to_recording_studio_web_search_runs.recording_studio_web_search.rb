# frozen_string_literal: true

class AddResultsToRecordingStudioWebSearchRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_web_search_runs, :results, :jsonb, null: false, default: []
  end
end
