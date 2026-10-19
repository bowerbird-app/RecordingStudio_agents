# frozen_string_literal: true

class AllowBlankRoleOnRecordingStudioAccessRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_null :recording_studio_access_requests, :role, true
  end
end
