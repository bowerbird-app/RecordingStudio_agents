# frozen_string_literal: true

module RecordingStudioAgents
  class AgentRun < ApplicationRecord
    self.table_name = "recording_studio_agents_agent_runs"

    STATUSES = %w[
      pending
      running
      awaiting_confirmation
      succeeded
      handoff_requested
      failed
      cancelled
    ].freeze

    belongs_to :task, class_name: "RecordingStudioAgents::Task"
    has_many :run_activities, class_name: "RecordingStudioAgents::RunActivity", dependent: :destroy
    has_many :evaluations, class_name: "RecordingStudioAgents::Evaluation", dependent: :destroy

    validates :status, inclusion: { in: STATUSES }
    validates :agent_key, :agent_version, :program_digest, :idempotency_key, presence: true
    validates :idempotency_key, uniqueness: { scope: %i[root_recording_id agent_key agent_version] }

    def activities
      run_activities.order(:sequence)
    end

    def selected_skill_key_list
      selected_skill_keys.join(",")
    end

    def selected_skill_labels
      selected_skill_keys.join(", ")
    end

    def selected_skill_keys
      Array(selected_skills_json).filter_map do |item|
        hash = item.respond_to?(:stringify_keys) ? item.stringify_keys : item
        key = hash["key"]
        next if key.blank?

        "#{key}:#{hash['version']}"
      end
    end

    def lease_expired?
      lease_expires_at.present? && lease_expires_at < Time.current
    end

    def progress
      Progress.for(self)
    end

    def record_evaluation(
      evaluator:,
      evaluator_key:,
      evaluator_version:,
      idempotency_key:,
      verdict:,
      score: nil,
      notes: nil,
      metadata: {}
    )
      Persistence::RunLedger.new.record_evaluation!(
        run: self,
        evaluator: evaluator,
        evaluator_key: evaluator_key,
        evaluator_version: evaluator_version,
        idempotency_key: idempotency_key,
        verdict: verdict,
        score: score,
        notes: notes,
        metadata: metadata
      )
    end
  end
end
