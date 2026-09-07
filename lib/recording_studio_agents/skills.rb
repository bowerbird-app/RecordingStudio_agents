# frozen_string_literal: true

require "recording_studio_agents/registry_store"

module RecordingStudioAgents
  module Skills
    class Definition
      attr_reader :key, :version, :name, :description, :instructions, :required_tools,
                  :use_when, :do_not_use_when

      def initialize(
        key:,
        version:,
        name:,
        description:,
        instructions:,
        required_tools:,
        use_when:,
        do_not_use_when:
      )
        @key = key.to_s
        @version = Integer(version)
        @name = name.to_s
        @description = description.to_s
        @instructions = instructions.to_s
        @required_tools = Array(required_tools).map { |reference| reference }
        @use_when = use_when.to_s
        @do_not_use_when = do_not_use_when.to_s
        Reference.new(key: @key, version: @version)
        validate!
        freeze
      end

      def reference
        Reference.new(key: key, version: version)
      end

      private

      def validate!
        raise ContractError, "skill name must be present" if name.strip.empty?
        raise ContractError, "skill instructions must be present" if instructions.strip.empty?
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
        required_tools: {},
        use_when: "",
        do_not_use_when: ""
      )
        tools = normalize_references(required_tools)
        definition = Definition.new(
          key: key,
          version: version,
          name: name,
          description: description,
          instructions: instructions,
          required_tools: tools,
          use_when: use_when,
          do_not_use_when: do_not_use_when
        )
        store(definition)
        definition
      end

      private

      def normalize_references(map)
        map.to_h.map { |tool_key, tool_version| Reference.new(key: tool_key, version: tool_version) }
      end
    end
  end
end
