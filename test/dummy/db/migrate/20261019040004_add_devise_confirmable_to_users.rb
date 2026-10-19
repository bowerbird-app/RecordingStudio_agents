class AddDeviseConfirmableToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string :unconfirmed_email
    end

    add_index :users, :confirmation_token, unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE users SET confirmed_at = CURRENT_TIMESTAMP WHERE confirmed_at IS NULL
        SQL
      end
    end
  end
end
