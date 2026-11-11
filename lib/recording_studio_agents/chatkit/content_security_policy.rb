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
      def origin_for(url)
        value = url.to_s.strip
        return unless value.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

        asset_origin(URI.parse(value))
      rescue URI::InvalidURIError
        nil
      end

      def asset_origin(uri)
        return unless uri.is_a?(URI::HTTP) && uri.host.present?
        return unless %w[http https].include?(uri.scheme)

        host = uri.host.downcase
        default_port = uri.scheme == "https" ? 443 : 80
        authority = uri.port == default_port ? host : "#{host}:#{uri.port}"
        "#{uri.scheme}://#{authority}"
      end
    end
  end
end
