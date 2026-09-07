# frozen_string_literal: true

module RecordingStudioAgents
  class TaskInput
    attr_reader :key, :goal, :context, :digest

    def initialize(key:, goal:, context: {})
      @key = key.to_s
      @goal = goal.to_s
      @context = RecordingStudioAI::Contracts::Containment.ensure_serializable!(
        context,
        path: "task.context"
      )
      validate!
      @digest = Digests.of("key" => @key, "goal" => @goal, "context" => @context)
      freeze
    end

    private

    def validate!
      raise ContractError, "task key must be present" if key.strip.empty?
      raise ContractError, "task goal must be present" if goal.strip.empty?
    end
  end
end
