# frozen_string_literal: true

class AddInstructionsToRecordingStudioAgentsSessions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    with_lock_timeout { add_instructions_column }
  end

  def down
    with_lock_timeout { remove_instructions_column }
  end

  private

  def add_instructions_column
    add_column :recording_studio_agents_sessions, :instructions, :text, if_not_exists: true
  end

  def remove_instructions_column
    return unless column_exists?(:recording_studio_agents_sessions, :instructions)

    remove_column :recording_studio_agents_sessions, :instructions
  end

  def with_lock_timeout
    previous = select_value("SHOW lock_timeout")
    execute "SET lock_timeout = '5s'"
    yield
  ensure
    restore_lock_timeout(previous)
  end

  def restore_lock_timeout(previous)
    return if previous.nil?

    execute "SET lock_timeout = #{quote(previous)}"
  end
end
