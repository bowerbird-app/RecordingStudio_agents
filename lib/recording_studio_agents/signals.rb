# frozen_string_literal: true

module RecordingStudioAgents
  class Signals
    REPEAT_LIMIT = 3

    def self.lines(state:, steps:, configuration:, started_at:)
      lines = []
      if state.data["no_progress_streak"].to_i.positive?
        lines << "no_progress_streak #{state.data['no_progress_streak']}"
      end
      lines << "repeated_action" if repeated_digest?(state)
      lines << "step_budget" if step_budget?(steps, configuration)
      lines << "tool_budget" if tool_budget?(state, configuration)
      lines << "runtime_budget" if runtime_budget?(started_at, configuration)
      lines << "candidate_exhaustion" if state.data["candidate_index"].empty?
      lines
    end

    def self.hard_stuck?(state)
      state.data["no_progress_streak"].to_i >= REPEAT_LIMIT || repeated_digest?(state)
    end

    def self.repeated_digest?(state)
      recent = state.data["attempted_digests"].last(REPEAT_LIMIT)
      recent.length == REPEAT_LIMIT && recent.uniq.length == 1
    end

    def self.over_budget?(state:, steps:, configuration:, started_at:)
      step_budget?(steps, configuration) ||
        tool_budget?(state, configuration) ||
        runtime_budget?(started_at, configuration)
    end

    def self.budget_code(state:, steps:, configuration:, started_at:)
      return "maximum_steps" if step_budget?(steps, configuration)
      return "maximum_tool_actions" if tool_budget?(state, configuration)
      return "maximum_runtime" if runtime_budget?(started_at, configuration)

      "budget"
    end

    def self.step_budget?(steps, configuration)
      steps >= configuration.maximum_steps
    end

    def self.tool_budget?(state, configuration)
      state.counter("tool_actions") >= configuration.maximum_tool_actions
    end

    def self.runtime_budget?(started_at, configuration)
      return false if started_at.nil?

      Time.current - started_at > configuration.maximum_runtime_seconds
    end
  end
end
