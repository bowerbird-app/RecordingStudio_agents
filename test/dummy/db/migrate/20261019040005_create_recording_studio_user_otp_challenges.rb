class CreateRecordingStudioUserOtpChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_user_otp_challenges, id: :uuid do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :purpose, null: false
      t.string :code_digest, null: false
      t.text :delivery_code_ciphertext
      t.datetime :expires_at, null: false
      t.integer :attempts_count, null: false, default: 0
      t.datetime :verified_at
      t.datetime :consumed_at
      t.datetime :revoked_at
      t.datetime :delivery_requested_at
      t.timestamps
    end

    add_index :recording_studio_user_otp_challenges, :expires_at
    add_index :recording_studio_user_otp_challenges, %i[user_id purpose]
    add_index :recording_studio_user_otp_challenges,
              %i[user_id purpose],
              unique: true,
              where: "consumed_at IS NULL AND revoked_at IS NULL",
              name: "index_rs_user_otp_challenges_open_purpose"
  end
end
