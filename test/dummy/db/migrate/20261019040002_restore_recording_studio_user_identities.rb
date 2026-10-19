# frozen_string_literal: true

class RestoreRecordingStudioUserIdentities < ActiveRecord::Migration[8.1]
  def up
    create_identities_table unless table_exists?(:recording_studio_user_identities)
    add_identity_indexes
    add_identity_foreign_key
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "The identities table may predate 0.6.2"
  end

  private

  def create_identities_table
    create_table :recording_studio_user_identities, id: :uuid do |t|
      t.uuid :user_id, null: false
      t.string :provider, :uid, null: false
      t.string :email
      t.timestamps null: false
    end
  end

  def add_identity_indexes
    add_index :recording_studio_user_identities, %i[provider uid], unique: true unless
      index_exists?(:recording_studio_user_identities, %i[provider uid], unique: true)
    add_index :recording_studio_user_identities, %i[user_id provider], unique: true unless
      index_exists?(:recording_studio_user_identities, %i[user_id provider], unique: true)
    add_index :recording_studio_user_identities, :user_id unless
      index_exists?(:recording_studio_user_identities, :user_id)
  end

  def add_identity_foreign_key
    return if foreign_key_exists?(:recording_studio_user_identities, :users, column: :user_id)

    add_foreign_key :recording_studio_user_identities, :users, column: :user_id
  end
end
