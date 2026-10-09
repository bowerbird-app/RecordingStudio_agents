# frozen_string_literal: true

require "test_helper"

class MetricsTest < Minitest::Test
  def test_metrics_register_with_operations_expose_and_staff_view
    metrics = File.read(File.expand_path("../lib/recording_studio_agents/metrics.rb", __dir__))
    access = File.read(File.expand_path("../lib/recording_studio_agents/api/access.rb", __dir__))
    engine = File.read(File.expand_path("../lib/recording_studio_agents/engine.rb", __dir__))
    gemspec = File.read(File.expand_path("../recording_studio_agents.gemspec", __dir__))
    dummy_metrics = File.read(File.expand_path("dummy/config/initializers/recording_studio_metrics.rb", __dir__))

    assert_includes metrics, "RecordingStudioMetrics.register"
    assert_includes metrics, ":agent_runs"
    assert_includes metrics, "RecordingStudioAgents::AgentRun"
    assert_includes metrics, "timeseries :over_time"
    assert_includes metrics, "field: :created_at"
    assert_includes metrics, "breakdown :by_status"
    assert_includes metrics, "field: :status"
    assert_includes metrics, "breakdown :by_agent"
    assert_includes metrics, "field: :agent_key"
    assert_includes metrics, ":agent_evaluations"
    assert_includes metrics, "RecordingStudioAgents::Evaluation"
    assert_includes metrics, "breakdown :by_verdict"
    assert_includes metrics, "field: :verdict"
    assert_includes metrics, "average :avg_score"
    assert_includes metrics, "field: :score"
    assert_includes metrics, "blast_radius: :site"
    assert_includes metrics, "expose: EXPOSE"
    assert_includes metrics, "api: [API]"
    assert_includes metrics, "API = :operations"
    assert_includes metrics, "Api::Access.can_view?"
    refute_includes metrics, "confirmable_column?"
    refute_includes metrics, "RecordingStudioMetrics::Api.register!"
    refute_includes metrics, "respond_to?"
    refute_includes metrics, "rescue"

    assert_includes access, "def can_view?"
    assert_includes access, "authorized_on_admin_root?(context, :view)"
    assert_includes access, "site_admin_recording_resolver || config.access_recording_resolver"
    assert_includes access, "rescue StandardError"
    assert_includes access, "RecordingStudioAccessible.authorized?"

    assert_includes metrics, "def install!"
    assert_includes metrics, 'initializer "recording_studio_agents.metrics"'
    assert_includes metrics, "RecordingStudioAgents::Metrics.register!"
    refute_includes engine, "RecordingStudioMetrics::Api.register!"
    refute_includes engine, "RecordingStudioAgents::Metrics"
    assert_includes File.read(File.expand_path("../lib/recording_studio_agents.rb", __dir__)),
                    "RecordingStudioAgents::Metrics.install!"
    assert(
      RecordingStudioAgents::Engine.initializers.any? do |entry|
        entry.name == "recording_studio_agents.metrics"
      end
    )

    assert_includes gemspec, 'spec.add_dependency "recording_studio_metrics", "~> 0.2"'
    refute_includes dummy_metrics, "RecordingStudioMetrics::Api.register!"
  end
end
