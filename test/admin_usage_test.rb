# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "action_controller"

class AdminUsageTest < PersistenceTestCase
  class UsageAiRun < ActiveRecord::Base
    self.table_name = "recording_studio_ai_runs"
  end

  FakeContext = Struct.new(:current_actor, :params, :admin_screen_path_prefix, :date_range, keyword_init: true) do
    def admin_screen_path(key)
      "#{admin_screen_path_prefix || '/admin/screens'}/#{key}"
    end

    def filter_value(key)
      date_range if key.to_sym == :date_range
    end
  end

  def setup
    super
    RecordingStudioAgents::Admin::Queries.clear_ai_run_cache!
    create_ai_runs_table!
    RecordingStudioAgents::Admin::Queries.use_ai_run_class!(UsageAiRun)
  end

  def teardown
    RecordingStudioAgents::Admin::Queries.clear_ai_run_cache!
    RecordingStudioAgents::Admin::Queries.reset_ai_run_class!
    super
  end

  def test_tokens_and_hungry_agents_join_ai_without_copying_onto_the_attempt
    now = Time.current
    librarian_ai = create_ai_run!(total_tokens: 12_000, tools: 4, latency_ms: 1800)
    reviewer_ai = create_ai_run!(total_tokens: 2_000, tools: 1, latency_ms: 400)
    create_agent_run!(
      agent_key: "page_librarian",
      status: "succeeded",
      ai_run_id: librarian_ai.id,
      created_at: now
    )
    create_agent_run!(
      agent_key: "page_reviewer",
      status: "succeeded",
      ai_run_id: reviewer_ai.id,
      created_at: now
    )
    create_agent_run!(
      agent_key: "page_librarian",
      status: "failed",
      ai_run_id: nil,
      created_at: now
    )
    create_agent_run!(
      agent_key: "support_clerk",
      status: "succeeded",
      ai_run_id: create_ai_run!(total_tokens: 8_000, tools: 2, latency_ms: 900).id,
      created_at: 70.days.ago
    )

    root_ids = [root.id]
    current = RecordingStudioAgents::Admin::Queries.current_period(now: now)
    previous = RecordingStudioAgents::Admin::Queries.previous_period(now: now)

    assert_equal 3, RecordingStudioAgents::Admin::Queries.attempts_in_period(root_ids: root_ids, range: current)
    assert_equal 0, RecordingStudioAgents::Admin::Queries.attempts_in_period(root_ids: root_ids, range: previous)
    assert_equal 14_000, RecordingStudioAgents::Admin::Queries.tokens_in_period(root_ids: root_ids, range: current)
    assert_equal 0, RecordingStudioAgents::Admin::Queries.tokens_in_period(root_ids: root_ids, range: previous)

    hungry = RecordingStudioAgents::Admin::Queries.hungry_agents(root_ids: root_ids, range: current)
    assert_equal(
      [
        { agent_key: "page_librarian", tokens: 12_000 },
        { agent_key: "page_reviewer", tokens: 2_000 }
      ],
      hungry
    )
    assert_equal "page_librarian · 12k tokens",
                 RecordingStudioAgents::Admin::Queries.hungry_label(agent_key: "page_librarian", tokens: 12_000)
    refute_includes RecordingStudioAgents::AgentRun.column_names, "total_tokens"
  end

  def test_by_agent_averages_skip_attempts_without_an_ai_row
    now = Time.current
    create_agent_run!(
      agent_key: "page_librarian",
      status: "succeeded",
      ai_run_id: create_ai_run!(total_tokens: 10_000, tools: 4, latency_ms: 2000).id,
      created_at: now
    )
    create_agent_run!(
      agent_key: "page_librarian",
      status: "failed",
      ai_run_id: nil,
      created_at: now
    )
    create_agent_run!(
      agent_key: "page_librarian",
      status: "awaiting_confirmation",
      ai_run_id: create_ai_run!(total_tokens: 2_000, tools: 2, latency_ms: 1000).id,
      created_at: now
    )

    rows = RecordingStudioAgents::Admin::Queries.by_agent_rows(
      root_ids: [root.id],
      range: RecordingStudioAgents::Admin::Queries.current_period(now: now)
    )

    assert_equal 1, rows.size
    row = rows.first
    assert_equal "page_librarian", row.agent_key
    assert_equal 3, row.attempts
    assert_equal 1, row.succeeded
    assert_equal 1, row.failed
    assert_equal 1, row.waiting
    assert_equal 6_000, row.avg_tokens
    assert_equal 1_500, row.avg_latency_ms
    assert_equal 3, row.avg_tools
    assert_equal 2, row.ai_sample_count
    assert_equal "-", RecordingStudioAgents::Admin::Queries.format_tokens(nil)
    assert_equal "6,000", RecordingStudioAgents::Admin::Queries.format_tokens(6_000)
  end

  def test_missing_ai_tables_return_blank_usage
    ActiveRecord::Base.connection.drop_table(:recording_studio_ai_runs)
    RecordingStudioAgents::Admin::Queries.clear_ai_run_cache!

    create_agent_run!(agent_key: "page_librarian", status: "succeeded", ai_run_id: 99)

    refute RecordingStudioAgents::Admin::Queries.ai_runs_available?
    assert_equal 0, RecordingStudioAgents::Admin::Queries.tokens_in_period(
      root_ids: [root.id],
      range: RecordingStudioAgents::Admin::Queries.current_period
    )
    assert_empty RecordingStudioAgents::Admin::Queries.hungry_agents(
      root_ids: [root.id],
      range: RecordingStudioAgents::Admin::Queries.current_period
    )
    row = RecordingStudioAgents::Admin::Queries.by_agent_rows(
      root_ids: [root.id],
      range: RecordingStudioAgents::Admin::Queries.current_period
    ).first
    assert_nil row.avg_tokens
    assert_equal "-", RecordingStudioAgents::Admin::Queries.format_tokens(row.avg_tokens)
  end

  def test_percentage_change_and_compact_tokens
    queries = RecordingStudioAgents::Admin::Queries

    assert_equal "0%", queries.percentage_change_label(current: 0, previous: 0)
    assert_equal "+100%", queries.percentage_change_label(current: 4, previous: 0)
    assert_equal "+50%", queries.percentage_change_label(current: 3, previous: 2)
    assert_equal "-50%", queries.percentage_change_label(current: 1, previous: 2)
    assert_equal "12k", queries.compact_tokens(12_000)
    assert_equal "1.2k", queries.compact_tokens(1_200)
    assert_equal "1.5M", queries.compact_tokens(1_500_000)
    assert_equal "12", queries.compact_tokens(12)
  end

  def test_cells_link_into_ai_screens_and_dash_without_an_ai_row
    context = FakeContext.new(current_actor: actor, params: {})
    linked = create_agent_run!(
      agent_key: "page_librarian",
      status: "succeeded",
      ai_run_id: create_ai_run!(total_tokens: 1_200, tools: 3, latency_ms: 100).id
    )
    missing = create_agent_run!(agent_key: "page_reviewer", status: "failed", ai_run_id: nil)

    tools_html = RecordingStudioAgents::Admin::Queries.tools_cell(linked, context)
    ai_html = RecordingStudioAgents::Admin::Queries.ai_run_cell(linked, context)

    assert_includes tools_html, "tool_calls?run_id=#{linked.recording_studio_ai_run_id}"
    assert_includes ai_html, "ai_calls?search=#{linked.recording_studio_ai_run_id}"
    assert_equal "-", RecordingStudioAgents::Admin::Queries.tools_cell(missing, context)
    assert_equal "-", RecordingStudioAgents::Admin::Queries.ai_run_cell(missing, context)
    assert_equal "-", RecordingStudioAgents::Admin::Queries.format_tokens(
      RecordingStudioAgents::Admin::Queries.ai_run_for(missing.recording_studio_ai_run_id)&.total_tokens
    )
  end

  def test_admin_screens_join_ai_and_resolve_hub_widgets
    RecordingStudioAgents::Admin.register!
    now = Time.current
    linked = create_agent_run!(
      agent_key: "page_librarian",
      status: "succeeded",
      ai_run_id: create_ai_run!(total_tokens: 1_200, tools: 3, latency_ms: 100).id,
      created_at: now
    )
    failed = create_agent_run!(agent_key: "page_reviewer", status: "failed", ai_run_id: nil, created_at: now)
    RecordingStudioAgents::Evaluation.create!(
      agent_run: linked,
      evaluator_key: "spot_check",
      evaluator_version: 1,
      idempotency_key: "eval:#{SecureRandom.uuid}",
      verdict: "passed"
    )
    context = FakeContext.new(current_actor: actor, params: {})
    queries = RecordingStudioAgents::Admin::Queries

    RecordingStudioAccessible.stub(:root_recording_ids_for, [root.id]) do
      assert_equal [root.id], queries.visible_root_ids(context)
      assert_equal 2, queries.runs(context: context).count
      assert_equal 2, queries.tasks(context: context).count
      assert_equal 1, queries.evaluations(context: context).count
      assert_equal [failed.id], queries.recent_failed_runs(context: context).map(&:id)
      assert_equal %w[page_librarian page_reviewer], queries.distinct_agent_keys

      window = Struct.new(:start_date, :end_date).new(Date.current - 7, Date.current)
      selected = queries.selected_time_range(
        FakeContext.new(date_range: window, params: {}),
        screen: RecordingStudioAgents::Admin::UsageScreen
      )
      assert_equal (Date.current - 7).beginning_of_day, selected.begin
      fallback = queries.selected_time_range(
        FakeContext.new(params: {}),
        screen: RecordingStudioAgents::Admin::UsageScreen
      )
      assert_kind_of Range, fallback
      assert_equal "-", queries.format_tools(nil)
      assert_equal "3", queries.format_tools(3)
      assert_equal "0", queries.compact_tokens(0)

      RecordingStudioAgents::Admin::Section.links_value.each do |link|
        assert_includes link.url.call(context), "/admin/screens/"
      end

      attempts = RecordingStudioAdmin.widget_for("widgets.agents.attempts_this_period").resolve(context)
      tokens = RecordingStudioAdmin.widget_for("widgets.agents.tokens_this_period").resolve(context)
      hungry = RecordingStudioAdmin.widget_for("widgets.agents.hungry_agents").resolve(context)
      failed_widget = RecordingStudioAdmin.widget_for("widgets.agents.failed_runs").resolve(context)

      assert_equal "2", attempts.value
      assert_equal "1,200", tokens.value
      assert_equal "page_librarian · 1.2k tokens", hungry.items.first[:text]
      assert_equal "page_reviewer · failed", failed_widget.items.first[:text]

      runs_query = RecordingStudioAgents::Admin::RunsScreen.query_value.call(context)
      assert_includes runs_query.map(&:id), linked.id
      usage_rows = RecordingStudioAgents::Admin::UsageScreen.query_value.call(context)
      assert_equal "page_librarian", usage_rows.first.agent_key

      RecordingStudioAgents::Admin::RunsScreen.table_value.columns.each do |column|
        column.value&.call(linked, context)
      end
      RecordingStudioAgents::Admin::UsageScreen.table_value.columns.each do |column|
        column.value&.call(usage_rows.first, context)
      end
    end

    queries.reset_ai_run_class!
    assert_nil queries.ai_run_class
  end

  private

  def create_ai_runs_table!
    return if ActiveRecord::Base.connection.data_source_exists?("recording_studio_ai_runs")

    ActiveRecord::Base.connection.create_table :recording_studio_ai_runs do |t|
      t.string :operation, null: false, default: "generation"
      t.string :status, null: false, default: "completed"
      t.string :initiator_type, null: false, default: "User"
      t.string :initiator_id, null: false, default: "1"
      t.string :initiator_kind, null: false, default: "user"
      t.string :root_recording_id, null: false, default: "root-1"
      t.integer :total_tokens
      t.integer :custom_tool_invocation_count, null: false, default: 0
      t.integer :latency_ms
      t.timestamps
    end
  end

  def create_ai_run!(total_tokens:, tools:, latency_ms:)
    UsageAiRun.create!(
      operation: "generation",
      status: "completed",
      initiator_type: "User",
      initiator_id: "1",
      initiator_kind: "user",
      root_recording_id: root.id,
      total_tokens: total_tokens,
      custom_tool_invocation_count: tools,
      latency_ms: latency_ms
    )
  end

  def create_agent_run!(agent_key:, status:, ai_run_id:, created_at: Time.current)
    task = RecordingStudioAgents::Task.create!(
      root_recording_id: root.id,
      task_key: "usage:#{SecureRandom.hex(4)}",
      goal: "Find Getting Started.",
      context_json: {},
      input_digest: "usage"
    )
    run = RecordingStudioAgents::AgentRun.create!(
      task: task,
      root_recording_id: root.id,
      agent_key: agent_key,
      agent_version: 1,
      program_digest: "usage",
      idempotency_key: "usage:#{SecureRandom.uuid}",
      status: status,
      recording_studio_ai_run_id: ai_run_id,
      initiator_type: "User",
      initiator_id: "1",
      initiator_kind: "user",
      execution_source: "web"
    )
    run.update_columns(created_at: created_at, updated_at: created_at)
    run
  end
end
