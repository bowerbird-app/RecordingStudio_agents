class AddOpenOtpChallengeIndex < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_rs_user_otp_challenges_open_purpose"

  def up
    return if index_exists?(:recording_studio_user_otp_challenges, %i[user_id purpose], name: INDEX_NAME)

    add_index :recording_studio_user_otp_challenges,
              %i[user_id purpose],
              unique: true,
              where: "consumed_at IS NULL AND revoked_at IS NULL",
              name: INDEX_NAME
  end

  def down
    remove_index :recording_studio_user_otp_challenges, name: INDEX_NAME, if_exists: true
  end
end
