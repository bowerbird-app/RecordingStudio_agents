# frozen_string_literal: true

module RecordingStudioAgents
  module Lifecycle
    TRANSITIONS = {
      "pending" => %w[running cancelled],
      "running" => %w[succeeded handoff_requested failed cancelled awaiting_confirmation],
      "awaiting_confirmation" => %w[running failed cancelled],
      "succeeded" => [],
      "handoff_requested" => [],
      "failed" => %w[running],
      "cancelled" => []
    }.freeze

    TERMINAL_STATES = %w[succeeded handoff_requested cancelled].freeze

    module_function

    def transition!(from:, to:)
      allowed = TRANSITIONS.fetch(from.to_s) { raise InvalidTransition, "unknown status #{from}" }
      return to.to_s if allowed.include?(to.to_s)

      raise InvalidTransition, "cannot move from #{from} to #{to}"
    end

    def terminal?(state)
      TERMINAL_STATES.include?(state.to_s)
    end
  end
end
