# frozen_string_literal: true

class AddFailedAndRateLimitedCountsToMcpUsageLogs < ActiveRecord::Migration[8.1]
  def change
    change_table :recording_studio_mcp_usage_logs do |t|
      t.virtual :failed_count, type: :integer, as: "CASE WHEN failed THEN 1 ELSE 0 END", stored: true
      t.virtual :rate_limited_count, type: :integer, as: "CASE WHEN rate_limited THEN 1 ELSE 0 END", stored: true
    end
  end
end
