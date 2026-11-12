# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # API 0.20 records the access-grant actor on a resource update. Older
    # releases leave event.actor empty for an in-process agent write.
    module ApiActor
      ACTOR_VERSION = Gem::Version.new("0.20")

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
        "Recording Studio Agents: recording_studio_api #{version} is older than 0.20. " \
          "event.actor will be empty for agent writes. Upgrade recording_studio_api to 0.20 or later."
      end
    end
  end
end
