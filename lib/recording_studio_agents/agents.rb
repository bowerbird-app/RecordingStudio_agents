# frozen_string_literal: true

require "recording_studio_agents/registry_store"

module RecordingStudioAgents
  module Agents
    class Definition
      attr_reader :key, :version, :name, :description, :instructions,
                  :skills, :optional_skills, :packs, :tools, :knowledge, :handoffs, :enabled

      def initialize(
        key:,
        version:,
        name:,
        description:,
        instructions:,
        skills:,
        optional_skills:,
        packs:,
        tools:,
        knowledge:,
        handoffs:,
        enabled:
      )
        @key = key.to_s
        @version = Integer(version)
        @name = name.to_s
        @description = description.to_s
        @instructions = instructions.to_s
        assign_lists(
          skills: skills,
          optional_skills: optional_skills,
          packs: packs,
          tools: tools,
          knowledge: knowledge,
          handoffs: handoffs
        )
        @enabled = enabled == true
        Reference.new(key: @key, version: @version)
        validate!
        freeze
      end

      def reference
        Reference.new(key: key, version: version)
      end

      private

      def assign_lists(skills:, optional_skills:, packs:, tools:, knowledge:, handoffs:)
        @skills = Array(skills)
        @optional_skills = Array(optional_skills)
        @packs = Array(packs)
        @tools = Array(tools)
        @knowledge = Array(knowledge)
        @handoffs = Array(handoffs)
      end

      def validate!
        raise ContractError, "agent name must be present" if name.strip.empty?
        raise ContractError, "agent instructions must be present" if instructions.strip.empty?
      end
    end

    class Registry
      include RegistryStore

      def register(
        key:,
        version:,
        name:,
        description:,
        instructions:,
        skills: {},
        optional_skills: {},
        packs: {},
        tools: {},
        knowledge: {},
        handoffs: {},
        enabled: true
      )
        definition = Definition.new(
          key: key,
          version: version,
          name: name,
          description: description,
          instructions: instructions,
          skills: normalize_references(skills),
          optional_skills: normalize_references(optional_skills),
          packs: normalize_references(packs),
          tools: normalize_references(tools),
          knowledge: normalize_references(knowledge),
          handoffs: normalize_references(handoffs),
          enabled: enabled
        )
        store(definition)
        definition
      end

      private

      def normalize_references(map)
        map.to_h.map { |item_key, item_version| Reference.new(key: item_key, version: item_version) }
      end
    end
  end
end
