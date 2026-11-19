class CreateRecordingStudioUserSignInLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_user_sign_in_links, id: :uuid do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }, type: :uuid, index: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :recording_studio_user_sign_in_links, :token_digest,
              unique: true, name: "index_rs_user_sign_in_links_on_token_digest"
    add_index :recording_studio_user_sign_in_links, :user_id,
              name: "index_rs_user_sign_in_links_on_user_id"
  end
end
