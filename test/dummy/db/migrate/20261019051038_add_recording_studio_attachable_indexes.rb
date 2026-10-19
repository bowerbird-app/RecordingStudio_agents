# frozen_string_literal: true

class AddRecordingStudioAttachableIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :recording_studio_recordings,
              :parent_recording_id,
              name: "idx_rs_attachable_parent_active",
              where: "recordable_type = 'RecordingStudioAttachable::Attachment' AND trashed_at IS NULL"

    add_index :recording_studio_recordings,
              :root_recording_id,
              name: "idx_rs_attachable_root_active",
              where: "recordable_type = 'RecordingStudioAttachable::Attachment' AND trashed_at IS NULL"
  end
end
