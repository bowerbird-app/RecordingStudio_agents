# frozen_string_literal: true

module RecordingStudioAgents
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    prepend_before_action :not_found_when_disabled

    recording_studio_layout { RecordingStudioAgents.configuration.layout }

    private

    def not_found_when_disabled
      head :not_found unless RecordingStudioAgents::Availability.enabled?(self)
    end
  end
end
