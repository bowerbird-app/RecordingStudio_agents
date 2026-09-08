# frozen_string_literal: true

require "test_helper"

class AdminRegistrationTest < Minitest::Test
  def test_register_adds_agents_section_screens_and_widgets
    RecordingStudioAgents::Admin.register!

    refute_nil RecordingStudioAdmin.section_for("agents")
    assert_equal "Agents", RecordingStudioAdmin.section_for("agents").title
    refute_nil RecordingStudioAdmin.screen_for("registered_agents")
    refute_nil RecordingStudioAdmin.screen_for("registered_skills")
    refute_nil RecordingStudioAdmin.screen_for("registered_skill_packs")
    refute_nil RecordingStudioAdmin.screen_for("agent_tasks")
    refute_nil RecordingStudioAdmin.screen_for("agent_runs")
    refute_nil RecordingStudioAdmin.screen_for("agent_evaluations")
    refute_nil RecordingStudioAdmin.screen_for("agent_usage")
    refute_nil RecordingStudioAdmin.widget_for("widgets.agents.failed_runs")
    refute_nil RecordingStudioAdmin.widget_for("widgets.agents.attempts_this_period")
    refute_nil RecordingStudioAdmin.widget_for("widgets.agents.tokens_this_period")
    refute_nil RecordingStudioAdmin.widget_for("widgets.agents.hungry_agents")
    assert_nil RecordingStudioAdmin.widget_for("widgets.agents.run_count")
    assert RecordingStudioAgents::Admin.registered?
  end

  def test_engine_registers_admin_on_to_prepare
    to_prepare_blocks = []
    config_stub = Object.new
    config_stub.define_singleton_method(:to_prepare) do |&block|
      to_prepare_blocks << block
    end

    RecordingStudioAgents::Engine.stub(:config, config_stub) do
      initializer = RecordingStudioAgents::Engine.initializers.find do |entry|
        entry.name == "recording_studio_agents.admin"
      end
      initializer.block.call
    end

    assert_equal 1, to_prepare_blocks.size
    RecordingStudioAgents::Admin.stub(:register!, true) do
      assert_equal true, to_prepare_blocks.first.call
    end
  end

  def test_queries_hide_rows_without_an_actor
    context = Struct.new(:current_actor).new(nil)

    assert_equal [], RecordingStudioAgents::Admin::Queries.visible_root_ids(context)
    assert_equal RecordingStudioAgents.agents.all, RecordingStudioAgents::Admin::Queries.agents
    assert_equal RecordingStudioAgents.skills.all, RecordingStudioAgents::Admin::Queries.skills
    assert_equal RecordingStudioAgents.skill_packs.all, RecordingStudioAgents::Admin::Queries.skill_packs
  end

  def test_register_aligns_last_4_weeks_with_flatpack
    RecordingStudioAgents::Admin.register!

    today = Date.new(2026, 9, 8)
    period = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks, reference_date: today)

    assert_equal today - 27, period.start_date
    assert_equal today, period.end_date
    assert_equal :last_4_weeks, period.preset_key
  end

  def test_last_4_weeks_alignment_leaves_other_presets_alone
    RecordingStudioAgents::Admin.register!

    today = Date.new(2026, 9, 8)
    period = RecordingStudioAdmin::Period.from_preset_key(:last_3_days, reference_date: today)

    assert_equal today - 2, period.start_date
    assert_equal today, period.end_date
    assert_equal :last_3_days, period.preset_key
  end

  def test_last_4_weeks_alignment_is_idempotent
    RecordingStudioAgents::Admin.register!
    RecordingStudioAgents::Admin.register!

    count = RecordingStudioAdmin::Period.singleton_class.ancestors.count do |mod|
      mod == RecordingStudioAgents::Admin::LastFourWeeksPeriod
    end

    assert_equal 1, count
  end

  def test_runs_and_usage_screens_default_to_last_4_weeks
    RecordingStudioAgents::Admin.register!

    runs = RecordingStudioAdmin.screen_for("agent_runs")
    usage = RecordingStudioAdmin.screen_for("agent_usage")
    runs_filter = runs.filters.find { |filter| filter.key == :date_range }
    usage_filter = usage.filters.find { |filter| filter.key == :date_range }

    assert_equal :last_4_weeks, runs_filter.options[:default]
    assert_equal :last_4_weeks, usage_filter.options[:default]
  end

  def test_last_four_weeks_lookback_matches_flatpack
    assert_equal 27, RecordingStudioAgents::Admin::LastFourWeeks::LOOKBACK_DAYS
  end
end
