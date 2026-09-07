# frozen_string_literal: true

require "recording_studio_agents/registry_store"

module RecordingStudioAgents
  module SkillPacks
    class Definition
      attr_reader :key, :version, :name, :description, :skills

      def initialize(key:, version:, name:, description:, skills:)
        @key = key.to_s
        @version = Integer(version)
        @name = name.to_s
        @description = description.to_s
        @skills = Array(skills)
        Reference.new(key: @key, version: @version)
        validate!
        freeze
      end

      def reference
        Reference.new(key: key, version: version)
      end

      private

      def validate!
        raise ContractError, "skill pack name must be present" if name.strip.empty?
        raise ContractError, "skill pack must list at least one skill" if skills.empty?
      end
    end

    class Registry
      include RegistryStore

      def register(key:, version:, name:, description:, skills:)
        definition = Definition.new(
          key: key,
          version: version,
          name: name,
          description: description,
          skills: normalize_references(skills)
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
