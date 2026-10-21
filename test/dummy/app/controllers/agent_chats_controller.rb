# frozen_string_literal: true

class AgentChatsController < ApplicationController
  def show
  end

  def page
    @page_recording = press_kit_page
  end

  private

  def press_kit_page
    root = current_root
    return if root.blank?

    RecordingStudio::Recording.for_root(root.id).where(recordable_type: "Page").find do |recording|
      recording.recordable.title == "Press kit"
    end
  end

  def current_root
    RecordingStudioAgents.configuration.request_root.call(self)
  end
end
