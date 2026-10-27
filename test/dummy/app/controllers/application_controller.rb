class ApplicationController < ActionController::Base
  include RecordingStudio::RootSwitchable::ControllerSupport

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  recording_studio_layout { RecordingStudioAgents.configuration.layout }

  before_action :authenticate_user!
  before_action :set_current_actor

  # Root Switchable's config.layout is :application_layout, so its controller calls this method.
  def application_layout
    recording_studio_resolved_layout
  end

  def recording_studio_resolved_layout
    return "application" if devise_controller?

    super
  end

  private

  def set_current_actor
    Current.actor = current_user
  end
end
