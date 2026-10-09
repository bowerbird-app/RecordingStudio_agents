# frozen_string_literal: true

require "test_helper"

class AgentMetricsApiTest < ActionDispatch::IntegrationTest
  OPERATIONS_ROOT = "/recording_studio_api/apis/operations/v1"
  PUBLIC_ROOT = "/recording_studio_api/api/v1"

  setup do
    @staff = User.create!(
      email: "metrics-staff-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    Current.actor = @staff
    @workspace = Workspace.create!(name: "Metrics #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @admin_root = RecordingStudio.root_recording_for(AdminRoot.find_or_create_by!(name: "Admin"))
    grant_accessible!(recording: @admin_root, actor: @staff, role: :admin)
    grant_accessible!(recording: @root, actor: @staff, role: :admin)

    seed_runs_and_evaluations!

    @staff_operations_token = provision_token(
      access_point: @admin_root,
      actor: @staff,
      role: :edit,
      name: "Staff operations metrics #{SecureRandom.hex(4)}",
      api: :operations
    )
    @workspace_operations_token = provision_token(
      access_point: @root,
      actor: @staff,
      role: :edit,
      name: "Workspace operations metrics #{SecureRandom.hex(4)}",
      api: :operations
    )
    @public_token = provision_token(
      access_point: @root,
      actor: @staff,
      role: :view,
      name: "Public metrics #{SecureRandom.hex(4)}"
    )
    Current.actor = nil
  end

  teardown do
    Current.actor = nil
  end

  test "operations staff token reads agent run and evaluation metrics" do
    get "#{OPERATIONS_ROOT}/metrics/agent_runs/by_status",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    status_counts = breakdown_counts(response.parsed_body)
    RecordingStudioAgents::AgentRun::STATUSES.each do |status|
      assert_equal RecordingStudioAgents::AgentRun.where(status: status).count, status_counts[status].to_i
    end

    get "#{OPERATIONS_ROOT}/metrics/agent_runs/by_agent",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    agent_counts = breakdown_counts(response.parsed_body)
    %w[page_librarian page_reviewer].each do |agent_key|
      assert_equal RecordingStudioAgents::AgentRun.where(agent_key: agent_key).count, agent_counts[agent_key].to_i
    end

    get "#{OPERATIONS_ROOT}/metrics/agent_runs/over_time",
        params: { interval: "month" },
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    opened = timeseries_counts(response.parsed_body)
    assert_equal runs_created_between(Time.utc(2026, 2, 1), Time.utc(2026, 3, 1)), opened["2026-02-01"]
    assert_equal runs_created_between(Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)), opened["2026-03-01"]
    assert_operator opened["2026-02-01"], :>=, 1
    assert_operator opened["2026-03-01"], :>=, 2

    get "#{OPERATIONS_ROOT}/metrics/agent_evaluations/by_verdict",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    verdict_counts = breakdown_counts(response.parsed_body)
    RecordingStudioAgents::Evaluation::VERDICTS.each do |verdict|
      assert_equal RecordingStudioAgents::Evaluation.where(verdict: verdict).count, verdict_counts[verdict].to_i
    end

    get "#{OPERATIONS_ROOT}/metrics/agent_evaluations/avg_score",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    expected_avg = RecordingStudioAgents::Evaluation.where.not(score: nil).average(:score).to_f
    assert_in_delta expected_avg, response.parsed_body.fetch("value").to_f, 0.001
  end

  test "metrics index lists agent run and evaluation metrics" do
    get "#{OPERATIONS_ROOT}/metrics", headers: auth(@staff_operations_token), as: :json

    assert_response :success
    identifiers = response.parsed_body.fetch("metrics").map { |row| row.fetch("identifier") }
    %w[
      agent_runs.over_time
      agent_runs.by_status
      agent_runs.by_agent
      agent_evaluations.by_verdict
      agent_evaluations.avg_score
    ].each { |identifier| assert_includes identifiers, identifier }
  end

  test "non-admin operations token is denied agent metrics" do
    get "#{OPERATIONS_ROOT}/metrics/agent_runs/by_status",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics/agent_evaluations/avg_score",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics", headers: auth(@workspace_operations_token), as: :json
    assert_response :success
    identifiers = response.parsed_body.fetch("metrics").map { |row| row.fetch("identifier") }
    refute_includes identifiers, "agent_runs.by_status"
    refute_includes identifiers, "agent_evaluations.avg_score"
  end

  test "public API token is denied operations agent metrics" do
    get "#{OPERATIONS_ROOT}/metrics/agent_runs/by_status",
        headers: auth(@public_token),
        as: :json
    assert_response :unauthorized

    get "#{OPERATIONS_ROOT}/metrics/agent_evaluations/by_verdict",
        headers: auth(@public_token),
        as: :json
    assert_response :unauthorized

    get "#{PUBLIC_ROOT}/metrics/agent_runs/by_status",
        headers: auth(@public_token),
        as: :json
    assert_includes [404, 401, 403], response.status
  end

  private

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

  def breakdown_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("key").to_s, row.fetch("value")] }
  end

  def timeseries_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("date").to_s, row.fetch("value").to_i] }
  end

  def runs_created_between(start_at, end_at)
    RecordingStudioAgents::AgentRun.where(created_at: start_at...end_at).count
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end

  def provision_token(access_point:, actor:, role:, name:, api: :public)
    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point,
      manager_actor: actor,
      role: role,
      name: name,
      api: api
    )
    raise result.error unless result.success?

    payload = result.value
    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token),
      api: api
    )
    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  end
end
