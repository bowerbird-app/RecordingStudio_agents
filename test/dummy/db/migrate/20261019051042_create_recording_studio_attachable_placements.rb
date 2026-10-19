# frozen_string_literal: true

class CreateRecordingStudioAttachablePlacements < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_attachable_placements, id: :uuid do |t|
      t.uuid :attachment_recording_id, null: false
      t.datetime :created_at, null: false

      t.index :attachment_recording_id
    end
  end
end
