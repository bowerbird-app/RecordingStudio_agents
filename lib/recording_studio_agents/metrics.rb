# frozen_string_literal: true

require_relative "api/access"
require "recording_studio_metrics"

module RecordingStudioAgents
  module Metrics
    RUNS = :agent_runs
    EVALUATIONS = :agent_evaluations
    API = :operations
    EXPOSE = { api: [API] }.freeze
    AUTHORIZE = ->(context) { RecordingStudioAgents::Api::Access.can_view?(context) }

    module_function

    def register!
      register_runs!
      register_evaluations!
    end

    def register_runs!
      RecordingStudioMetrics.register(
        RUNS,
        model: RecordingStudioAgents::AgentRun,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioAgents::Metrics.define_runs(self) }
    end

    def register_evaluations!
      RecordingStudioMetrics.register(
        EVALUATIONS,
        model: RecordingStudioAgents::Evaluation,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioAgents::Metrics.define_evaluations(self) }
    end

    def define_runs(dsl)
      dsl.timeseries :over_time, title: "Agent runs over time", field: :created_at, expose: EXPOSE
      dsl.breakdown :by_status, title: "Agent runs by status", field: :status, expose: EXPOSE
      dsl.breakdown :by_agent, title: "Agent runs by agent", field: :agent_key, expose: EXPOSE
    end

    def define_evaluations(dsl)
      dsl.breakdown :by_verdict, title: "Evaluations by verdict", field: :verdict, expose: EXPOSE
      dsl.average :avg_score, title: "Average evaluation score", field: :score, expose: EXPOSE
    end
  end
end
