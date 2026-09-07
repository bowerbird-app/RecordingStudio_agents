# frozen_string_literal: true

require "digest"
require "json"
require "timeout"

require "recording_studio"
require "recording_studio_ai"
require "recording_studio_admin"
require "recording_studio_accessible"

require "recording_studio_agents/version"
require "recording_studio_agents/errors"
require "recording_studio_agents/digests"
require "recording_studio_agents/configuration"
require "recording_studio_agents/reference"
require "recording_studio_agents/task_input"
require "recording_studio_agents/skills"
require "recording_studio_agents/knowledge"
require "recording_studio_agents/agents"
require "recording_studio_agents/skill_packs"
require "recording_studio_agents/skill_selection"
require "recording_studio_agents/programs"
require "recording_studio_agents/results"
require "recording_studio_agents/lifecycle"
require "recording_studio_agents/ai"
require "recording_studio_agents/handoffs"
require "recording_studio_agents/persistence"
require "recording_studio_agents/progress"
require "recording_studio_agents/execution"
require "recording_studio_agents/agent"
require "recording_studio_agents/admin"
require "recording_studio_agents/engine"

module RecordingStudioAgents
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def skills
      @skills ||= Skills::Registry.new
    end

    def knowledge
      @knowledge ||= Knowledge::Registry.new
    end

    def agents
      @agents ||= Agents::Registry.new
    end

    def skill_packs
      @skill_packs ||= SkillPacks::Registry.new
    end

    def agent(key, version:)
      definition = agents.fetch(key, version: version)
      raise AgentDisabled.new(key, version) unless definition.enabled

      Agent.new(definition: definition)
    end

    def reset!
      @skills = Skills::Registry.new
      @knowledge = Knowledge::Registry.new
      @agents = Agents::Registry.new
      @skill_packs = SkillPacks::Registry.new
    end

    def finalize!
      Handoffs::Tool.register!
      agents.all.map { |definition| Programs::Compiler.compile(definition: definition) }
    end
  end
end
