# frozen_string_literal: true

module RecordingStudioAgents
  module Enablement
    module_function

    def enabled?(agent)
      default = agent.enabled
      return default unless persistable?

      record = AgentEnablement.find_by(agent_key: agent.key, agent_version: agent.version)
      record.nil? ? default : record.enabled
    end

    def set!(agent:, enabled:)
      raise ConfigurationError, "agent on/off is not available" unless persistable?

      record = AgentEnablement.find_or_initialize_by(
        agent_key: agent.key,
        agent_version: agent.version
      )
      record.enabled = enabled
      record.save!
      record
    end

    def persistable?
      return false unless defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
      return false unless RecordingStudioAgents.const_defined?(:AgentEnablement)

      AgentEnablement.table_exists?
    rescue StandardError
      false
    end
  end
end
