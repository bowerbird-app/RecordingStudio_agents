# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # Sources the popup page needs for the ChatKit web component. Applied on
    # that action only. The host's application-wide policy is left alone.
    module ContentSecurityPolicy
      SCRIPT_HOST = "https://cdn.platform.openai.com"
      CONNECT_HOSTS = [SCRIPT_HOST, "https://api.openai.com"].freeze
      FRAME_HOSTS = [SCRIPT_HOST].freeze

      module_function

      def apply(policy, script_origin = nil)
        policy.script_src :self, SCRIPT_HOST, *Array(script_origin.presence)
        policy.connect_src :self, *CONNECT_HOSTS
        policy.frame_src :self, *FRAME_HOSTS
        policy.frame_ancestors :self, *RecordingStudioAgents.configuration.chatkit_allowed_origins
      end

      # Origin of an absolute asset URL. A relative URL is covered by 'self'.
      # Same parser as chatkit_allowed_origins.
      def origin_for(url)
        ChatkitHostSettings.origin(url)
      end
    end
  end
end
