# frozen_string_literal: true

module RecordingStudioAgents
  class Binding < ApplicationRecord
    self.table_name = "recording_studio_agents_bindings"

    belongs_to :recording, class_name: "RecordingStudio::Recording"
    belongs_to :root_recording, class_name: "RecordingStudio::Recording"

    validates :provider, :create_idempotency_key, :last_activity_at, :expires_at, presence: true

    before_validation :copy_root_recording

    scope :expired, ->(at = Time.current) { where(expires_at: ..at) }

    private

    def copy_root_recording
      return if recording.nil?

      self.root_recording_id = recording.root_recording_id
    end
  end
end
