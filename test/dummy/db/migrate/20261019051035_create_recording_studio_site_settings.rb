# frozen_string_literal: true

class CreateRecordingStudioSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_site_settings, id: :uuid do |t|
      t.string :name, null: false
      t.datetime :created_at, null: false
    end
  end
end
