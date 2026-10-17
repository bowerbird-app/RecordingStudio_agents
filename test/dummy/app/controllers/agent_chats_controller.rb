# frozen_string_literal: true

class AgentChatsController < ApplicationController
  def show
    ensure_demo_access
  end

  private

  def ensure_demo_access
    root = RecordingStudioAgents.configuration.request_root.call(self)
    return if root.blank?
    return if RecordingStudioAccessible.authorized?(actor: current_user, recording: root, role: :edit)

    RecordingStudioAccessible::AccessCreationContext.allow do
      root.record(RecordingStudio::Access, actor: current_user, parent_recording: root) do |access|
        access.actor = current_user
        access.role = "edit"
      end
    end
  end
end
