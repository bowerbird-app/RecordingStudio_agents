# frozen_string_literal: true

module RecordingStudioAgents
  # Recording Studio AI 0.21.1 checks attribution with a validator that accepts
  # only Recording instances. Agents.stream then rebuilds the same attribution
  # from the run as an object that has an id and nothing else, and that check
  # raises. This replaces the default validator. A host-assigned validator stays.
  module AiAttribution
    module_function

    def install!
      configuration = RecordingStudioAI.configuration
      current = configuration.attribution_validator
      return unless default_validator?(current)

      configuration.attribution_validator = method(:call)
    end

    def call(root_recording:, context_recording:)
      root = root!(root_recording)
      return if context_recording.nil?
      return if in_root?(context_recording, root)

      raise ArgumentError, "context_recording must belong to root_recording"
    end

    def root!(value)
      found = as_root(value) || lookup_root(value)
      return found if found

      raise ArgumentError, "root_recording must be a Recording Studio root"
    end

    def default_validator?(current)
      current.is_a?(Method) && current.original_name == :validate_recording_attribution!
    end

    def as_root(value)
      value if root?(value)
    end

    def lookup_root(value)
      return unless value.respond_to?(:id)

      found = RecordingStudio::Recording.find_by(id: value.id)
      found if root?(found)
    end

    def in_root?(recording, root)
      recording.is_a?(RecordingStudio::Recording) && recording.root_recording_id == root.id
    end

    def root?(value)
      value.is_a?(RecordingStudio::Recording) &&
        value.parent_recording_id.nil? &&
        value.root_recording_id == value.id
    end
  end
end
