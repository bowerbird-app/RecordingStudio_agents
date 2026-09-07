# frozen_string_literal: true

require "test_helper"

class AdminRegistrationTest < Minitest::Test
  def test_register_adds_agents_section_screens_and_widgets
    RecordingStudioAgents::Admin.register!

    refute_nil RecordingStudioAdmin.section_for("agents")
    assert_equal "Agents", RecordingStudioAdmin.section_for("agents").title
    refute_nil RecordingStudioAdmin.screen_for("registered_agents")
    refute_nil RecordingStudioAdmin.screen_for("registered_skills")
    refute_nil RecordingStudioAdmin.screen_for("agent_tasks")
    refute_nil RecordingStudioAdmin.screen_for("agent_runs")
    refute_nil RecordingStudioAdmin.screen_for("agent_evaluations")
    refute_nil RecordingStudioAdmin.widget_for("widgets.agents.failed_runs")
    refute_nil RecordingStudioAdmin.widget_for("widgets.agents.run_count")
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
  end
end
