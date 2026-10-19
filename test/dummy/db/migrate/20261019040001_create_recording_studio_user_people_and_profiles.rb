# frozen_string_literal: true

class CreateRecordingStudioUserPeopleAndProfiles < ActiveRecord::Migration[8.1]
  def change
    create_people_table
    create_profiles_table
  end

  private

  def create_people_table
    create_table :recording_studio_user_people, id: :uuid do |t|
      t.datetime :created_at, null: false
    end
  end

  def create_profiles_table
    create_table :recording_studio_user_profiles, id: :uuid do |t|
      t.uuid :user_id, null: false
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :time_zone, null: false, default: "UTC"
      t.jsonb :additional_profile_attributes, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_profile_indexes
  end

  def add_profile_indexes
    add_index :recording_studio_user_profiles, :user_id
    add_foreign_key :recording_studio_user_profiles, :users, column: :user_id
  end
end
