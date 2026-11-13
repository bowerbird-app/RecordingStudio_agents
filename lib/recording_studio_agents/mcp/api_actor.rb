# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # In-process creates need API 0.21.2, which keys idempotency as
    # actor:<Type>:<id>. Older releases warn at boot when MCP tools are on.
    module ApiActor
      ACTOR_VERSION = Gem::Version.new("0.21.2")

      module_function

      def warn_if_needed
        version = outdated_api_version
        return if version.nil?

        logger = rails_logger
        return if logger.nil?

        logger.warn(warning_message(version))
      end

      def outdated_api_version
        return unless RecordingStudioAgents.configuration.mcp_tools == :write

        version = Gem.loaded_specs["recording_studio_api"]&.version
        version if version && version < ACTOR_VERSION
      end

      def rails_logger
        return unless defined?(Rails) && Rails.respond_to?(:logger)

        Rails.logger
      end

      def warning_message(version)
        "Recording Studio Agents: recording_studio_api #{version} is older than 0.21.2. " \
          "In-process creates need 0.21.2 so idempotency is keyed as actor:<Type>:<id>. " \
          "Upgrade recording_studio_api to 0.21.2 or later."
      end
    end
  end
end
