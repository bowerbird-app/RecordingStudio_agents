# frozen_string_literal: true

require "test_helper"

class RegistriesTest < Minitest::Test
  include RegistryHelpers

  def test_register_and_fetch_skill
    skill = RecordingStudioAgents.skills.register(
      key: :lookup,
      version: 1,
      name: "Lookup",
      description: "Find things",
      instructions: "Use the find tool.",
      required_tools: { find_page: 1 }
    )

    fetched = RecordingStudioAgents.skills.fetch(:lookup, version: 1)
    assert_equal skill, fetched
    assert_equal "lookup", fetched.key
    assert_equal 1, fetched.required_tools.first.version
  end

  def test_duplicate_registration_raises
    attrs = {
      key: :lookup,
      version: 1,
      name: "Lookup",
      description: "Find things",
      instructions: "Use the find tool."
    }
    RecordingStudioAgents.skills.register(**attrs)
    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents.skills.register(**attrs)
    end
    assert_match(/already registered/, error.message)
  end

  def test_agent_lookup_raises_when_disabled
    RecordingStudioAgents.agents.register(
      key: :quiet,
      version: 1,
      name: "Quiet",
      description: "Off",
      instructions: "Do nothing.",
      enabled: false
    )

    error = assert_raises(RecordingStudioAgents::AgentDisabled) do
      RecordingStudioAgents.agent(:quiet, version: 1)
    end
    assert_equal "quiet", error.key
  end

  def test_admin_can_fetch_disabled_agent
    RecordingStudioAgents.agents.register(
      key: :quiet,
      version: 1,
      name: "Quiet",
      description: "Off",
      instructions: "Do nothing.",
      enabled: false
    )

    definition = RecordingStudioAgents.agents.fetch(:quiet, version: 1)
    refute definition.enabled
  end

  def test_task_input_digest_is_stable
    first = RecordingStudioAgents::TaskInput.new(key: "a", goal: "Find it", context: { "id" => 1 })
    second = RecordingStudioAgents::TaskInput.new(key: "a", goal: "Find it", context: { "id" => 1 })
    assert_equal first.digest, second.digest
  end

  def test_task_input_rejects_blank_goal
    assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents::TaskInput.new(key: "a", goal: " ")
    end
  end

  def test_fetch_missing_skill_raises
    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents.skills.fetch(:missing, version: 1)
    end
    assert_match(/no missing version 1/, error.message)
  end

  def test_skill_keeps_use_when_metadata
    skill = RecordingStudioAgents.skills.register(
      key: :lookup,
      version: 1,
      name: "Lookup",
      description: "Find things",
      instructions: "Use the find tool.",
      use_when: "The task names a page.",
      do_not_use_when: "The task asks to rename a page."
    )

    assert_equal "The task names a page.", skill.use_when
    assert_equal "The task asks to rename a page.", skill.do_not_use_when
  end

  def test_register_and_fetch_skill_pack
    RecordingStudioAgents.skills.register(
      key: :billing_help,
      version: 1,
      name: "Billing help",
      description: "Refunds",
      instructions: "Explain the refund window."
    )
    pack = RecordingStudioAgents.skill_packs.register(
      key: :billing_tickets,
      version: 1,
      name: "Billing tickets",
      description: "Refund and invoice questions.",
      skills: { billing_help: 1 }
    )

    fetched = RecordingStudioAgents.skill_packs.fetch(:billing_tickets, version: 1)
    assert_equal pack, fetched
    assert_equal "billing_help", fetched.skills.first.key
  end

  def test_duplicate_skill_pack_registration_raises
    RecordingStudioAgents.skills.register(
      key: :billing_help,
      version: 1,
      name: "Billing help",
      description: "Refunds",
      instructions: "Explain the refund window."
    )
    attrs = {
      key: :billing_tickets,
      version: 1,
      name: "Billing tickets",
      description: "Refund and invoice questions.",
      skills: { billing_help: 1 }
    }
    RecordingStudioAgents.skill_packs.register(**attrs)
    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents.skill_packs.register(**attrs)
    end
    assert_match(/already registered/, error.message)
  end

  def test_skill_pack_requires_a_name_and_skills
    assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents.skill_packs.register(
        key: :empty,
        version: 1,
        name: " ",
        description: "Nope",
        skills: { billing_help: 1 }
      )
    end
    assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents.skill_packs.register(
        key: :empty,
        version: 1,
        name: "Empty",
        description: "Nope",
        skills: {}
      )
    end
  end

  def test_agent_handle_is_not_a_precompiled_program
    register_librarian
    handle = RecordingStudioAgents.agent(:librarian, version: 1)

    assert_equal "librarian", handle.key
    assert_equal 1, handle.version
    assert_equal "librarian", handle.program.key
  end
end
