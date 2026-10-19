# frozen_string_literal: true

class AddGateMetadataToRecordingStudioAccessRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_access_requests, :gate_metadata, :jsonb, null: false, default: {}
  end
end
