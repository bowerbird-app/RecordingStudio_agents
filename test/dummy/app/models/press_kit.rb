class PressKit < ApplicationRecord
  recording_studio_recordable label: "Press kit", root: false, allowed_parent_types: [ "Workspace" ]
  include RecordingStudio::Capabilities::Agents.to
  include RecordingStudio::Capabilities::Attachable.to(
    allowed_content_types: [ "image/*" ],
    max_file_size: 2.megabytes,
    max_file_count: 12,
    enabled_attachment_kinds: %i[image]
  )

  validates :name, presence: true
end
