# frozen_string_literal: true

module RecordingStudioAgents
  class Session < ApplicationRecord
    self.table_name = "recording_studio_agents_sessions"
    self.filter_attributes += [:instructions]

    recording_studio_recordable label: "Chat", root: false

    RecordingStudio.enable_capability(:accessible, on: self) if defined?(RecordingStudioAccessible)

    STATUSES = %w[active closed].freeze

    validates :status, inclusion: { in: STATUSES }
    validates :model, presence: true
    validates :purpose, format: { with: /\A[a-z0-9_]+\z/ }, allow_nil: true
  end
end
