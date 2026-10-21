class PressKit < ApplicationRecord
  recording_studio_recordable label: "Press kit", root: false, allowed_parent_types: [ "Workspace" ]
  include RecordingStudio::Capabilities::Agents.to
  include RecordingStudio::Capabilities::Attachable.to(
    allowed_content_types: [ "image/*" ],
    max_file_size: 2.megabytes,
    max_file_count: 12,
    enabled_attachment_kinds: %i[image]
  )
  RecordingStudio.enable_capability(:accessible, on: self) if defined?(RecordingStudioAccessible)

  validates :name, presence: true

  # Seeds store heading, paragraph, and quote blocks. The show page renders
  # those kinds. It does not guess a heading from a short line of capitals.
  def display_blocks
    structured = normalized_sections
    return structured if structured.any?

    content.to_s.split(/\n\n+/).filter_map do |paragraph|
      text = paragraph.strip
      next if text.empty?

      kind = text.start_with?("“") ? "quote" : "paragraph"
      { "kind" => kind, "text" => text }
    end
  end

  private

  def normalized_sections
    Array(sections).filter_map do |entry|
      next unless entry.is_a?(Hash)

      kind = entry["kind"].to_s
      text = entry["text"].to_s.strip
      next if text.empty?
      next unless %w[heading paragraph quote].include?(kind)

      { "kind" => kind, "text" => text }
    end
  end
end
