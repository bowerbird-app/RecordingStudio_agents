# frozen_string_literal: true

module RecordingStudioAgents
  class Agent
    attr_reader :program

    def initialize(program:)
      @program = program
    end

    def key
      program.key
    end

    def version
      program.version
    end

    def name
      program.name
    end

    def run(
      task:,
      root_recording:,
      initiator:,
      execution_source:,
      idempotency_key:,
      context_recording: nil,
      initiator_kind: :user,
      executor: nil
    )
      request = Execution::Request.parse(
        task: task,
        root_recording: root_recording,
        initiator: initiator,
        execution_source: execution_source,
        idempotency_key: idempotency_key,
        context_recording: context_recording,
        initiator_kind: initiator_kind,
        executor: executor
      )
      Execution::Engine.new(program: program).call(request: request)
    end
  end
end
