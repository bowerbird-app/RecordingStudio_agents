class CreateRecordingStudioUserSignInLockouts < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_user_password_failures, id: :uuid do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }, type: :uuid, index: false
      t.timestamps
    end
    add_index :recording_studio_user_password_failures, %i[user_id created_at],
              name: "index_rs_user_password_failures_on_user_and_created_at"

    create_table :recording_studio_user_sign_in_locks, id: :uuid do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }, type: :uuid, index: false
      t.string :kind, null: false
      t.datetime :locked_at, null: false
      t.datetime :notified_at
      t.timestamps
    end
    add_index :recording_studio_user_sign_in_locks, %i[user_id kind locked_at],
              name: "index_rs_user_sign_in_locks_on_user_kind_locked_at"
  end
end
