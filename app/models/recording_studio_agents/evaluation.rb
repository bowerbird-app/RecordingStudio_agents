# frozen_string_literal: true

module RecordingStudioAgents
  class Evaluation < ApplicationRecord
    self.table_name = "recording_studio_agents_evaluations"

    VERDICTS = %w[passed failed inconclusive].freeze

    belongs_to :agent_run, class_name: "RecordingStudioAgents::AgentRun"

    validates :evaluator_key, :evaluator_version, :idempotency_key, presence: true
    validates :verdict, inclusion: { in: VERDICTS }
    validate :score_in_range

    private

    def score_in_range
      return if score.nil?
      return if score.between?(0, 1)

      errors.add(:score, "must be between 0 and 1")
    end
  end
end
