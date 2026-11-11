# frozen_string_literal: true

module RecordingStudioAgents
  class PopupsController < ApplicationController
    include RequestContext

    helper_method :popup_sign_in_path

    content_security_policy only: :show do |policy|
      ChatKit::ContentSecurityPolicy.apply(policy)
    end

    after_action :drop_frame_options, only: :show

    def show
      @actor = recording_studio_agents_resolve(:request_actor)
      @root = recording_studio_agents_resolve(:request_root) if @actor.present?
    end

    def recording_studio_resolved_layout
      "recording_studio_agents/popup"
    end

    def popup_sign_in_path
      path = RecordingStudioAgents.configuration.sign_in_path
      path.respond_to?(:call) ? path.call(self) : path
    end

    private

    def drop_frame_options
      response.headers.delete("X-Frame-Options")
    end
  end
end
