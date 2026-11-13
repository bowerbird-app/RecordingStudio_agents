# frozen_string_literal: true

class CreateRecordingStudioAgentsChatToolAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_agents_chat_tool_audits, id: :uuid, &method(:columns)
    add_index :recording_studio_agents_chat_tool_audits, :occurred_at
    add_index :recording_studio_agents_chat_tool_audits, :chat_recording_id,
              name: "index_rs_agents_chat_tool_audits_on_chat"
    add_index :recording_studio_agents_chat_tool_audits, :provider_turn_id,
              name: "index_rs_agents_chat_tool_audits_on_turn"
  end

  def columns(table)
    table.datetime :occurred_at, null: false
    table.string :actor_type
    table.string :actor_id
    table.uuid :chat_recording_id
    required_strings(table)
    table.jsonb :argument_keys, null: false, default: []
    table.string :provider_turn_id
    table.integer :round_number
    table.timestamps
  end

  def required_strings(table)
    %i[tool_name kind outcome call_id].each { |name| table.string name, null: false }
  end
end
