# frozen_string_literal: true

class CreateRecordingStudioAttachableLibraries < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_attachable_libraries, id: :uuid do |t|
      t.string :key, null: false, default: "default"
      t.datetime :created_at, null: false
    end

    add_index :recording_studio_attachable_libraries, :key
  end
end
