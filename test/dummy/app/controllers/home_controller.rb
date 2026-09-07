# frozen_string_literal: true

class HomeController < ApplicationController
  helper_method :progress_heading

  def index
    root = current_root_recording
    @latest_run = latest_librarian_run(root)
    @progress_steps = @latest_run ? RecordingStudioAgents::Progress.for(@latest_run) : []
  end

  private

  def latest_librarian_run(root)
    return unless root

    RecordingStudioAgents::AgentRun.where(
      root_recording_id: root.id,
      agent_key: "page_librarian"
    ).order(created_at: :desc).first
  end

  def progress_heading
    return "On it" if @latest_run&.status == "running"

    "What it did"
  end
end
