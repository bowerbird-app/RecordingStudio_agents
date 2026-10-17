class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
  include RecordingStudio::Capabilities::Example.to(label: "dummy workspace")
  include RecordingStudio::Capabilities::Agents.to
  RecordingStudio.enable_capability(:accessible, on: self) if defined?(RecordingStudioAccessible)
end
