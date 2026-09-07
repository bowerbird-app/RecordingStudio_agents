# frozen_string_literal: true

class CreateAdminAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_audit_logs, id: :uuid do |t|
      t.string :event_id, null: false
      t.string :resource_key, null: false
      t.string :action_key, null: false
      t.string :outcome, null: false
      t.string :actor_type
      t.string :actor_id
      t.string :record_type
      t.string :record_id
      t.uuid :access_recording_id
      t.string :surface_key
      t.string :http_method
      t.boolean :destructive
      t.string :required_role
      t.string :blast_radius
      t.string :request_id
      t.string :ip_address
      t.string :user_agent
      t.jsonb :metadata, null: false, default: {}
      t.string :error_class
      t.text :error_message
      t.string :recording_studio_event_id
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :admin_audit_logs, :event_id, unique: true
    add_index :admin_audit_logs, :occurred_at
    add_index :admin_audit_logs, %i[resource_key action_key]
    add_index :admin_audit_logs, :outcome
  end
end
