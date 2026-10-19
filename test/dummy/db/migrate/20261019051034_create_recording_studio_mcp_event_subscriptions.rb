# frozen_string_literal: true

class CreateRecordingStudioMcpEventSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_mcp_event_subscriptions, id: :string do |t|
      t.string :owner_principal_id, null: false
      t.uuid :access_recording_id
      t.string :event_name, null: false
      t.jsonb :arguments, null: false, default: {}
      t.string :callback_url, null: false
      t.text :callback_secret, null: false
      t.string :status, null: false, default: "active"
      t.datetime :expires_at, null: false
      t.datetime :last_delivered_at
      t.string :last_error
      t.integer :failure_count, null: false, default: 0

      t.timestamps
    end

    add_index :recording_studio_mcp_event_subscriptions, :owner_principal_id,
              name: "index_rs_mcp_event_subs_on_owner"
    add_index :recording_studio_mcp_event_subscriptions, %i[event_name status],
              name: "index_rs_mcp_event_subs_on_event_and_status"
  end
end
