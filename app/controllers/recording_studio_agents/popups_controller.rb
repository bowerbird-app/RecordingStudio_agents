# frozen_string_literal: true

module RecordingStudioAgents
  class PopupsController < ApplicationController
    helper_method :popup_sign_in_path

    content_security_policy only: :show do |policy|
      ChatKit::ContentSecurityPolicy.apply(policy)
    end

    after_action :drop_frame_options, only: :show

    def show
      @actor = resolve_actor
    end

    def recording_studio_resolved_layout
      "recording_studio_agents/popup"
    end

    def popup_sign_in_path
      path = RecordingStudioAgents.configuration.sign_in_path
      path.respond_to?(:call) ? path.call(self) : path
    end

    private

    def resolve_actor
      resolver = RecordingStudioAgents.configuration.request_actor
      resolver.respond_to?(:call) ? resolver.call(self) : nil
    end

    def drop_frame_options
      response.headers.delete("X-Frame-Options")
    end
  end
end
