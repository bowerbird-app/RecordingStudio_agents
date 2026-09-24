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
      extra_skills: {},
      skills: nil,
      tools: nil,
      profile: nil
    )
      selection = selection_for(pack: pack, extra_skills: extra_skills, skills: skills)
      compiled = Programs::Compiler.compile(definition: definition, selection: selection, tools: tools)
      request = Execution::Request.parse(
        task: task,
        root_recording: root_recording,
        initiator: initiator,
        execution_source: execution_source,
        idempotency_key: idempotency_key,
        context_recording: context_recording,
        initiator_kind: initiator_kind,
        executor: executor,
        selection: selection,
        profile: Profiles.resolve(profile, definition.profile)
      )
      Execution::Engine.new(program: compiled).call(request: request)
    end

    private

    def selection_for(pack:, extra_skills:, skills:)
      return SkillSelection.parse(definition: definition, pack: pack, extra_skills: extra_skills || {}) if skills.nil?

      raise ContractError, "skills replaces pack and extra skills" if pack.present? || extra_skills.present?

      SkillSelection.explicit(skills: skills)
    end
  end
end
