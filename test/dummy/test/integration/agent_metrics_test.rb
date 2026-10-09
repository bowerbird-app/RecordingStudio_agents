# frozen_string_literal: true

require "test_helper"

class AgentMetricsTest < ActiveSupport::TestCase
  GrantContext = Struct.new(:access_grant)
  Grant = Struct.new(:actor)

  setup do
    @staff = User.create!(
      email: "metrics-staff-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    @outsider = User.create!(
      email: "metrics-outsider-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    Current.actor = @staff
    @workspace = Workspace.create!(name: "Metrics #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @admin_root = RecordingStudio.root_recording_for(AdminRoot.find_or_create_by!(name: "Admin"))
    grant!(@admin_root, @staff, :admin)
    bootstrap_owner!(@root, @staff)
    seed_runs_and_evaluations!
    Current.actor = nil
  end

  teardown do
    Current.actor = nil
  end

  test "registered agent metrics return seeded run and evaluation values" do
    identifiers = RecordingStudioMetrics.definitions.map(&:identifier)
    %w[
      agent_runs.over_time
      agent_runs.by_status
      agent_runs.by_agent
      agent_evaluations.by_verdict
      agent_evaluations.avg_score
    ].each { |identifier| assert_includes identifiers, identifier }

    opened = timeseries_counts(
      execute(
        "agent_runs.over_time",
        interval: "month",
        start_at: Time.utc(2026, 2, 1),
        end_at: Time.utc(2026, 4, 1)
      )
    )
    assert_equal runs_created_between(Time.utc(2026, 2, 1), Time.utc(2026, 3, 1)), opened["2026-02-01"]
    assert_equal runs_created_between(Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)), opened["2026-03-01"]
    assert_operator opened["2026-02-01"], :>=, 1
    assert_operator opened["2026-03-01"], :>=, 2

    status_counts = breakdown_counts(execute("agent_runs.by_status"))
    RecordingStudioAgents::AgentRun::STATUSES.each do |status|
      assert_equal RecordingStudioAgents::AgentRun.where(status: status).count, status_counts[status].to_i
    end

    agent_counts = breakdown_counts(execute("agent_runs.by_agent"))
    %w[page_librarian page_reviewer].each do |agent_key|
      assert_equal RecordingStudioAgents::AgentRun.where(agent_key: agent_key).count, agent_counts[agent_key].to_i
    end

    verdict_counts = breakdown_counts(execute("agent_evaluations.by_verdict"))
    RecordingStudioAgents::Evaluation::VERDICTS.each do |verdict|
      assert_equal RecordingStudioAgents::Evaluation.where(verdict: verdict).count, verdict_counts[verdict].to_i
    end

    expected_avg = RecordingStudioAgents::Evaluation.where.not(score: nil).average(:score).to_f
    assert_in_delta expected_avg, execute("agent_evaluations.avg_score").value.to_f, 0.001
  end

  test "api_authorize allows AdminRoot staff and denies non-admins" do
    authorize = RecordingStudioMetrics.registry.api_authorize_for(:agent_runs)
    assert_equal RecordingStudioAgents::Metrics::AUTHORIZE, authorize

    assert authorize.call(GrantContext.new(Grant.new(@staff)))
    refute authorize.call(GrantContext.new(Grant.new(@outsider)))
    refute authorize.call(GrantContext.new(Grant.new(nil)))
  end

  private

  def execute(identifier, **params)
    RecordingStudioMetrics.execute(
      identifier,
      context: site_context,
      cache: false,
      **params
    )
  end

  def site_context
    RecordingStudioMetrics::Context.new(
      scope: :site,
      actor: @staff,
      site_authorized: true,
      timezone: "UTC"
    )
  end

  def seed_runs_and_evaluations!
    travel_to Time.utc(2026, 2, 10, 12) do
      create_run!(agent_key: "page_librarian", status: "succeeded", suffix: "feb10-ok")
    end
    travel_to Time.utc(2026, 3, 11, 12) do
      failed = create_run!(agent_key: "page_librarian", status: "failed", suffix: "mar11-fail")
      running = create_run!(agent_key: "page_reviewer", status: "running", suffix: "mar11-run")
      create_evaluation!(run: failed, verdict: "failed", score: 0.2, suffix: "fail")
      create_evaluation!(run: running, verdict: "inconclusive", score: 0.5, suffix: "wait")
    end
    travel_to Time.utc(2026, 3, 12, 12) do
      succeeded = create_run!(agent_key: "page_reviewer", status: "succeeded", suffix: "mar12-ok")
      create_evaluation!(run: succeeded, verdict: "passed", score: 0.9, suffix: "pass")
    end
  end

  def create_run!(agent_key:, status:, suffix:)
    task = RecordingStudioAgents::Task.create!(
      root_recording_id: @root.id,
      task_key: "metrics:#{suffix}",
      goal: "Measure #{suffix}.",
      input_digest: "metrics-#{suffix}"
    )
    RecordingStudioAgents::AgentRun.create!(
      task: task,
      root_recording_id: @root.id,
      agent_key: agent_key,
      agent_version: 1,
      program_digest: "metrics-#{suffix}",
      idempotency_key: "metrics:#{suffix}",
      status: status,
      initiator_type: "User",
      initiator_id: @staff.id,
      initiator_kind: "user",
      execution_source: "test"
    )
  end

  def create_evaluation!(run:, verdict:, score:, suffix:)
    RecordingStudioAgents::Evaluation.create!(
      agent_run: run,
      evaluator_key: "metrics_reviewer",
      evaluator_version: 1,
      idempotency_key: "metrics:eval:#{suffix}",
      verdict: verdict,
      score: score
    )
  end

  def runs_created_between(start_at, end_at)
    RecordingStudioAgents::AgentRun.where(created_at: start_at...end_at).count
  end

  def breakdown_counts(result)
    result.data.to_h { |row| [row[:key].to_s, row[:value] || row["value"]] }
  end

  def timeseries_counts(result)
    result.data.to_h { |row| [(row[:date] || row["date"]).to_s, row[:value] || row["value"]] }
  end

  def bootstrap_owner!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: recording,
      actor: actor
    )
    raise result.error if result.failure?
  end

  def grant!(recording, actor, role)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: @staff
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
