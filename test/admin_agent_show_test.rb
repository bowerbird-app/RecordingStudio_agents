# frozen_string_literal: true

require "test_helper"
require "action_controller"

class AdminAgentShowTest < Minitest::Test
  include RegistryHelpers

  FakeContext = Struct.new(:params, :admin_screen_path_prefix, keyword_init: true) do
    def admin_screen_path(key)
      "#{admin_screen_path_prefix || '/admin/screens'}/#{key}"
    end
  end

  def setup
    super
    RecordingStudioAgents::Admin.register!
  end

  def test_register_adds_the_agent_show_screen
    refute_nil RecordingStudioAdmin.screen_for("registered_agent")
    assert_equal "registered_agent", RecordingStudioAgents::Admin::AgentShowScreen.key
  end

  def test_hub_keeps_agent_details_off_the_catalog
    links = RecordingStudioAgents::Admin::Section.links_value
    catalog = links.select { |link| link.visible_if.nil? }.map(&:text)
    agent = links.find { |link| link.name == :agent }

    assert_equal ["Agents", "Runs", "Tasks", "Usage by agent", "Evaluations"], catalog
    assert_equal "Agent", agent.text
    refute agent.visible?(FakeContext.new(params: {}))
    assert agent.visible?(FakeContext.new(params: { agent_key: "librarian" }))
  end

  def test_show_copy_uses_the_registered_agent
    register_librarian
    found = FakeContext.new(params: { agent_key: "librarian", version: 1 })
    missing = FakeContext.new(params: { agent_key: "missing_agent" })
    queries = RecordingStudioAgents::Admin::Queries

    assert_equal "Librarian", queries.agent_show_title(found)
    assert_equal "Finds pages", queries.agent_show_subtitle(found)
    assert_equal "Agent", queries.agent_show_title(missing)
    assert_equal "That agent is not on the list.", queries.agent_show_subtitle(missing)
  end

  def test_detail_rows_list_what_the_agent_uses
    register_librarian
    agent = RecordingStudioAgents::Admin::Queries.agent_definition("librarian", version: 1)
    rows = RecordingStudioAgents::Admin::Queries.agent_detail_rows(agent)
    by_label = rows.to_h { |row| [row.label, row.value] }

    assert_equal "librarian", by_label.fetch("Key")
    assert_equal 1, by_label.fetch("Version")
    assert_equal "On", by_label.fetch("Enabled")
    assert_equal "Find the named page.", by_label.fetch("Instructions")
    assert_equal "Lookup", by_label.fetch("Skills")
    assert_equal "None", by_label.fetch("Extra skills")
    assert_equal "None", by_label.fetch("Skill packs")
    assert_equal "find page", by_label.fetch("Tools")
    assert_equal "None", by_label.fetch("Knowledge")
    assert_equal "None", by_label.fetch("Can pass to")
  end

  def test_detail_rows_name_optional_skills_and_packs
    register_support_clerk
    agent = RecordingStudioAgents::Admin::Queries.agent_definition("support_clerk")
    rows = RecordingStudioAgents::Admin::Queries.agent_detail_rows(agent)
    by_label = rows.to_h { |row| [row.label, row.value] }

    assert_equal "Support voice", by_label.fetch("Skills")
    assert_equal "Billing help, Login help", by_label.fetch("Extra skills")
    assert_equal "Billing tickets", by_label.fetch("Skill packs")
    assert_equal "lookup invoice", by_label.fetch("Tools")
  end

  def test_name_cell_links_to_the_show_screen
    register_librarian
    agent = RecordingStudioAgents::Admin::Queries.agent_definition("librarian", version: 1)
    html = RecordingStudioAgents::Admin::Queries.agent_name_cell(
      agent,
      FakeContext.new(params: {})
    )

    assert_includes html, "Librarian"
    assert_includes html, "/admin/screens/registered_agent?"
    assert_includes html, "agent_key=librarian"
    assert_includes html, "version=1"
  end

  def test_show_screen_query_is_empty_when_the_agent_is_missing
    context = FakeContext.new(params: { agent_key: "missing_agent" })
    rows = RecordingStudioAgents::Admin::AgentShowScreen.query_value.call(context)

    assert_equal [], rows
  end
end
