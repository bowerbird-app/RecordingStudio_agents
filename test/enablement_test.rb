# frozen_string_literal: true

require "test_helper"

class EnablementTest < PersistenceTestCase
  def test_registry_off_blocks_lookup
    register_quiet_agent(enabled: false)

    error = assert_raises(RecordingStudioAgents::AgentDisabled) do
      RecordingStudioAgents.agent(:quiet, version: 1)
    end
    assert_equal "quiet", error.key
    refute RecordingStudioAgents::Enablement.enabled?(
      RecordingStudioAgents.agents.fetch(:quiet, version: 1)
    )
  end

  def test_admin_override_turns_a_registered_agent_off
    register_librarian
    agent = RecordingStudioAgents.agents.fetch(:librarian, version: 1)

    assert RecordingStudioAgents::Enablement.enabled?(agent)
    RecordingStudioAgents::Enablement.set!(agent: agent, enabled: false)

    refute RecordingStudioAgents::Enablement.enabled?(agent)
    assert agent.enabled
    assert_raises(RecordingStudioAgents::AgentDisabled) do
      RecordingStudioAgents.agent(:librarian, version: 1)
    end
  end

  def test_admin_override_turns_a_registered_agent_on
    register_quiet_agent(enabled: false)
    agent = RecordingStudioAgents.agents.fetch(:quiet, version: 1)

    RecordingStudioAgents::Enablement.set!(agent: agent, enabled: true)

    assert RecordingStudioAgents::Enablement.enabled?(agent)
    refute agent.enabled
    handle = RecordingStudioAgents.agent(:quiet, version: 1)
    assert_equal "quiet", handle.key
  end

  def test_set_is_idempotent_for_the_same_agent
    register_librarian
    agent = RecordingStudioAgents.agents.fetch(:librarian, version: 1)

    RecordingStudioAgents::Enablement.set!(agent: agent, enabled: false)
    RecordingStudioAgents::Enablement.set!(agent: agent, enabled: false)
    RecordingStudioAgents::Enablement.set!(agent: agent, enabled: true)

    assert RecordingStudioAgents::Enablement.enabled?(agent)
    assert_equal 1, RecordingStudioAgents::AgentEnablement.count
  end

  private

  def register_quiet_agent(enabled:)
    RecordingStudioAgents.agents.register(
      key: :quiet,
      version: 1,
      name: "Quiet",
      description: "Off",
      instructions: "Do nothing.",
      enabled: enabled
    )
  end
end
