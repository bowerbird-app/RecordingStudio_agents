# frozen_string_literal: true

class PressKitsController < ApplicationController
  def index
    @press_kits = press_kits.select { |recording| viewable?(recording) }
  end

  def show
    recording = press_kits.find { |candidate| candidate.id == params[:id] }
    if recording.nil?
      @press_kit = nil
      @images = []
      render status: :not_found
      return
    end

    unless viewable?(recording)
      @press_kit = nil
      @images = []
      @press_kit_forbidden = true
      render status: :forbidden
      return
    end

    @press_kit = recording
    @images = gallery(recording)
  end

  private

  # Same split as ScopedParent: missing from this workspace is 404, and a kit
  # that is here but not viewable is 403.
  def viewable?(recording)
    RecordingStudioAccessible.authorized?(actor: Current.actor, recording: recording, role: :view)
  end

  def press_kits
    root = current_root
    return [] if root.blank?

    RecordingStudio::Recording.for_root(root.id).where(recordable_type: "PressKit").filter_map do |recording|
      next if recording.respond_to?(:trashed_at) && recording.trashed_at.present?

      recording
    end.sort_by { |recording| recording.recordable.name.to_s }
  end

  def gallery(recording)
    recording.images(per_page: 24).sort_by { |image| [ image.created_at, image.id.to_s ] }
  end

  def current_root
    RecordingStudioAgents.configuration.request_root.call(self)
  end
end
