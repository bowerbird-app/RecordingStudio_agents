# frozen_string_literal: true

class AdminRoot < ApplicationRecord
  include RecordingStudio::Recordable
  include RecordingStudioAdmin::AllowsAdminSections

  recording_studio_recordable label: "Admin", root: true, shared: false
  RecordingStudio.enable_capability(:accessible, on: self)

  recording_studio_admin_sections do
    section :root
    section :agents
    section :recording_studio_ai
    section :web_search
  end
end
