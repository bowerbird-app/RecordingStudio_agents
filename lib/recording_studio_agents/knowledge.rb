# frozen_string_literal: true

require "recording_studio_agents/registry_store"

module RecordingStudioAgents
  module Knowledge
    TIMEOUT_SECONDS = 5
    MAXIMUM_ENTRIES = 40
    MAXIMUM_BYTES = 32 * 1024

    class Entry
      attr_reader :key, :title, :content, :source_recording

      def initialize(key:, title:, content:, source_recording: nil)
        @key = key.to_s
        @title = title.to_s
        @content = content.to_s
        @source_recording = source_recording
        raise ContractError, "knowledge entry key must be present" if @key.strip.empty?
        raise ContractError, "knowledge entry title must be present" if @title.strip.empty?

        freeze
      end

      def byte_size
        content.bytesize
      end
    end

    class Context
      attr_reader :task, :root_recording, :context_recording, :initiator, :executor

      def initialize(task:, root_recording:, context_recording:, initiator:, executor:)
        @task = task
        @root_recording = root_recording
        @context_recording = context_recording
        @initiator = initiator
        @executor = executor
        freeze
      end
    end

    class Definition
      attr_reader :key, :version, :name, :description, :loader

      def initialize(key:, version:, name:, description:, loader:)
        @key = key.to_s
        @version = Integer(version)
        @name = name.to_s
        @description = description.to_s
        @loader = loader
        Reference.new(key: @key, version: @version)
        raise ContractError, "knowledge loader must respond to call" unless loader.respond_to?(:call)

        freeze
      end

      def load(context)
        entries = loader.call(context)
        unless entries.is_a?(Array) && entries.all? { |entry| entry.is_a?(Entry) }
          raise ConfigurationError, "knowledge #{key} loader must return an Array of Entry"
        end

        entries
      end

      def reference
        Reference.new(key: key, version: version)
      end
    end

    class Registry
      include RegistryStore

      def register(key:, version:, name:, description:, loader:)
        definition = Definition.new(
          key: key,
          version: version,
          name: name,
          description: description,
          loader: loader
        )
        store(definition)
        definition
      end
    end

    module Gatherer
      module_function

      def load(definitions:, context:)
        entries = []
        definitions.each do |definition|
          loaded = Timeout.timeout(TIMEOUT_SECONDS) { definition.load(context) }
          entries.concat(loaded)
        rescue Timeout::Error
          raise ConfigurationError, "knowledge #{definition.key} timed out after #{TIMEOUT_SECONDS}s"
        end

        entries.each { |entry| assert_contained!(entry, context.root_recording) }
        assert_limits!(entries)
        entries
      end

      def assert_contained!(entry, root_recording)
        source = entry.source_recording
        return if source.nil?

        root_id = identifier(root_recording)
        source_id = identifier(source)
        return if source_id == root_id

        source_root_id = source.respond_to?(:root_recording_id) ? source.root_recording_id : nil
        return if source_root_id == root_id

        raise ConfigurationError, "knowledge entry #{entry.key} is outside the task root"
      end

      def assert_limits!(entries)
        if entries.length > MAXIMUM_ENTRIES
          raise ConfigurationError, "knowledge produced #{entries.length} entries; maximum is #{MAXIMUM_ENTRIES}"
        end

        total = entries.sum(&:byte_size)
        return if total <= MAXIMUM_BYTES

        raise ConfigurationError, "knowledge produced #{total} bytes; maximum is #{MAXIMUM_BYTES}"
      end

      def identifier(value)
        value.respond_to?(:id) ? value.id : value
      end
    end
  end
end
