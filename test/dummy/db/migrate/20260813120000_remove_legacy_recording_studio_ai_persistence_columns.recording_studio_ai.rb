# frozen_string_literal: true

class RemoveLegacyRecordingStudioAIPersistenceColumns < ActiveRecord::Migration[8.1]
  def change
    %i[initiator_snapshot executor_snapshot impersonator_snapshot input_digest output_digest].each do |column|
      remove_column :recording_studio_ai_runs, column, if_exists: true
    end
    %i[arguments_digest arguments_summary result_digest].each do |column|
      remove_column :recording_studio_ai_custom_tool_invocations, column, if_exists: true
    end
    %i[initiator_snapshot executor_snapshot impersonator_snapshot].each do |column|
      remove_column :recording_studio_ai_batches, column, if_exists: true
    end
  end
end
