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
    skill = links.find { |link| link.name == :skill }
    tool = links.find { |link| link.name == :tool }
    refute skill.visible?(FakeContext.new(params: {}))
    assert skill.visible?(FakeContext.new(params: { skill_key: "lookup" }))
    refute tool.visible?(FakeContext.new(params: {}))
    assert tool.visible?(FakeContext.new(params: { tool_key: "find_page" }))
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

  def test_detail_rows_link_skills_and_tools
    register_librarian
    agent = RecordingStudioAgents::Admin::Queries.agent_definition("librarian", version: 1)
    context = FakeContext.new(params: {})
    rows = RecordingStudioAgents::Admin::Queries.agent_detail_rows(agent, context)
    by_label = rows.to_h { |row| [row.label, row.value.to_s] }

    assert_includes by_label.fetch("Skills"), "Lookup"
    assert_includes by_label.fetch("Skills"), "/admin/screens/registered_skill?"
    assert_includes by_label.fetch("Skills"), "skill_key=lookup"
    assert_includes by_label.fetch("Tools"), "find page"
    assert_includes by_label.fetch("Tools"), "/admin/screens/registered_tool?"
    assert_includes by_label.fetch("Tools"), "tool_key=find_page"
  end

  def test_skill_show_lists_instructions_and_linked_tools
    register_librarian
    context = FakeContext.new(params: { skill_key: "lookup", version: 1 })
    queries = RecordingStudioAgents::Admin::Queries
    skill = queries.selected_skill(context)
    rows = queries.skill_detail_rows(skill, context)
    by_label = rows.to_h { |row| [row.label, row.value.to_s] }

    assert_equal "Lookup", queries.skill_show_title(context)
    assert_equal "Find pages", queries.skill_show_subtitle(context)
    assert_equal "lookup", by_label.fetch("Key")
    assert_equal "Use find_page.", by_label.fetch("Instructions")
    assert_includes by_label.fetch("Tools"), "registered_tool?"
    assert_includes by_label.fetch("Tools"), "tool_key=find_page"
  end

  def test_tool_show_lists_what_the_tool_does
    register_librarian
    context = FakeContext.new(params: { tool_key: "find_page", version: 1 })
    queries = RecordingStudioAgents::Admin::Queries
    tool = queries.selected_tool(context)
    rows = queries.tool_detail_rows(tool)
    by_label = rows.to_h { |row| [row.label, row.value] }

    assert_equal "find page", queries.tool_show_title(context)
    assert_equal "Test tool", queries.tool_show_subtitle(context)
    assert_equal "find_page", by_label.fetch("Key")
    assert_equal "Looks only", by_label.fetch("Effect")
    assert_equal "Off", by_label.fetch("Needs a yes")
  end

  def test_register_adds_the_skill_and_tool_show_screens
    refute_nil RecordingStudioAdmin.screen_for("registered_skill")
    refute_nil RecordingStudioAdmin.screen_for("registered_tool")
  end

  def test_show_screen_query_is_empty_when_the_agent_is_missing
    context = FakeContext.new(params: { agent_key: "missing_agent" })
    rows = RecordingStudioAgents::Admin::AgentShowScreen.query_value.call(context)

    assert_equal [], rows
  end
end
