# frozen_string_literal: true

module RecordingStudioAgents
  class Agent
    attr_reader :definition

    def initialize(definition:)
      @definition = definition
    end

    def key
      definition.key
    end

    def version
      definition.version
    end

    def name
      definition.name
    end

    def program
      Programs::Compiler.compile(definition: definition)
    end

    def run(
      task:,
      root_recording:,
      initiator:,
      execution_source:,
      idempotency_key:,
      context_recording: nil,
      initiator_kind: :user,
      executor: nil,
      pack: nil,
      extra_skills: {}
    )
      selection = SkillSelection.parse(
        definition: definition,
        pack: pack,
        extra_skills: extra_skills || {}
      )
      compiled = Programs::Compiler.compile(definition: definition, selection: selection)
      request = Execution::Request.parse(
        task: task,
        root_recording: root_recording,
        initiator: initiator,
        execution_source: execution_source,
        idempotency_key: idempotency_key,
        context_recording: context_recording,
        initiator_kind: initiator_kind,
        executor: executor,
        selection: selection
      )
      Execution::Engine.new(program: compiled).call(request: request)
    end
  end
end
