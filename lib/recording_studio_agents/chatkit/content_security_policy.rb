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

      def apply(policy, request = nil)
        policy.script_src :self, SCRIPT_HOST, *Array(asset_script_host(request))
        policy.connect_src :self, *CONNECT_HOSTS
        policy.frame_src :self, *FRAME_HOSTS
        policy.frame_ancestors :self, *RecordingStudioAgents.configuration.chatkit_allowed_origins
      end

      def asset_script_host(request)
        normalize_asset_host(resolve_asset_host(request))
      end

      def resolve_asset_host(request)
        host = configured_asset_host
        return if host.blank?
        return host unless host.respond_to?(:call)
        return if request.nil?

        host.call(request).presence
      end

      def configured_asset_host
        base_host = action_controller_base_asset_host
        return base_host if asset_host_set?(base_host)

        config = defined?(Rails) ? Rails.application&.config : nil
        return unless config

        action_host = action_controller_asset_host(config)
        return action_host if asset_host_set?(action_host)

        config.asset_host if config.respond_to?(:asset_host)
      end

      def action_controller_base_asset_host
        return unless defined?(ActionController::Base) && ActionController::Base.respond_to?(:asset_host)

        ActionController::Base.asset_host
      end

      def action_controller_asset_host(config)
        return unless config.respond_to?(:action_controller)

        controller = config.action_controller
        controller.asset_host if controller.respond_to?(:asset_host)
      end

      def asset_host_set?(host)
        return false if host.nil?
        return true if host.respond_to?(:call)

        !host.blank?
      end

      def normalize_asset_host(raw)
        value = raw.to_s.strip
        return if value.empty?

        value = "https://#{value.delete_prefix('//')}" unless value.include?("://")
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
