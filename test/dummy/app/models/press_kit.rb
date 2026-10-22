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

  before_save :replace_sections_from_content, if: :replace_sections_from_content?
  after_save :clear_section_source_flags

  # A revise copies attributes without calling these writers. The flag is set
  # only when this save assigns the field, which is how an MCP content edit
  # is told apart from a copied sections list.
  def content=(value)
    @content_was_set = true
    super
  end

  def sections=(value)
    @sections_were_set = true
    super
  end

  # Seeds store heading, paragraph, and quote blocks. The show page renders
  # those kinds. It does not guess a heading from a short line of capitals.
  # An edit that sets content, and does not set sections in the same save,
  # rebuilds the blocks from that content so the page shows the edit.
  def display_blocks
    structured = normalized_sections
    return structured if structured.any?

    blocks_from_content(content)
  end

  private

  def clear_section_source_flags
    @content_was_set = false
    @sections_were_set = false
  end

  def replace_sections_from_content?
    @content_was_set && !@sections_were_set
  end

  def replace_sections_from_content
    write_attribute(:sections, blocks_from_content(content))
  end

  def blocks_from_content(text)
    text.to_s.split(/\n\n+/).filter_map do |paragraph|
      body = paragraph.strip
      next if body.empty?

      kind = body.start_with?("“") ? "quote" : "paragraph"
      { "kind" => kind, "text" => body }
    end
  end

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
