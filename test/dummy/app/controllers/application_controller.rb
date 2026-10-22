class ApplicationController < ActionController::Base
  include RecordingStudio::RootSwitchable::ControllerSupport

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Devise keeps the host layout. Other pages use Recording Studio's default shell.
  # Nil lets RecordingStudio.configuration.layout, then the default layout, apply.
  recording_studio_layout { devise_controller? ? "application" : nil }

  before_action :authenticate_user!
  before_action :set_current_actor

  private

  # Root Switchable calls this when config.layout is :application_layout.
  def application_layout
    devise_controller? ? "application" : "recording_studio/default_layout"
  end

  def set_current_actor
    Current.actor = current_user
  end
end
