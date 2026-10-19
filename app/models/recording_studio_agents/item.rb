# frozen_string_literal: true

module RecordingStudioAgents
  class Item < ApplicationRecord
    self.table_name = "recording_studio_agents_items"

    belongs_to :recording, class_name: "RecordingStudio::Recording"
    belongs_to :root_recording, class_name: "RecordingStudio::Recording"

    validates :role, :text, :status, presence: true
  end
end
