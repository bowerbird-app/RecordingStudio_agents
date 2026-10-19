# frozen_string_literal: true

class AddPresentationToRecordingStudioAttachableAttachments < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_attachable_attachments, :caption, :text
    add_column :recording_studio_attachable_attachments, :credit, :text
    add_column :recording_studio_attachable_attachments, :alt_text, :text
  end
end
