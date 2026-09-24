# frozen_string_literal: true

require "test_helper"

class ProfileTest < PersistenceTestCase
  def setup
    super
    @previous_profile = RecordingStudioAgents.configuration.profile
  end

  def teardown
    RecordingStudioAgents.configuration.profile = @previous_profile
    super
  end

  def test_an_agent_can_pin_a_profile
    definition = RecordingStudioAgents.agents.register(
      key: :quiet,
      version: 1,
      name: "Quiet",
      description: "Off",
      instructions: "Do nothing.",
      profile: "Low"
    )

    assert_equal :low, definition.profile
    assert_nil RecordingStudioAgents.agents.register(
      key: :plain,
      version: 1,
      name: "Plain",
      description: "On",
      instructions: "Do the work."
    ).profile
  end

  def test_an_unknown_profile_is_rejected
    error = assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents.agents.register(
        key: :quiet,
        version: 1,
        name: "Quiet",
        description: "Off",
        instructions: "Do nothing.",
        profile: "turbo"
      )
    end

    assert_match(/low, medium, high/, error.message)
  end

  def test_a_run_uses_medium_when_nobody_names_a_profile
    register_librarian

    assert_equal :medium, captured_profile
  end

  def test_a_run_uses_the_agent_profile
    register_librarian
    pin_librarian(:low)

    assert_equal :low, captured_profile(version: 2)
  end

  def test_a_run_profile_wins_over_the_agent
    register_librarian
    pin_librarian(:low)

    assert_equal :high, captured_profile(version: 2, profile: :high)
  end

  def test_the_host_profile_applies_when_the_agent_does_not_pin_one
    register_librarian
    RecordingStudioAgents.configuration.profile = :high

    assert_equal :high, captured_profile
  end

  def test_a_blank_run_profile_keeps_the_agent_profile
    register_librarian
    pin_librarian(:low)

    assert_equal :low, captured_profile(version: 2, profile: " ")
  end

  def test_a_run_rejects_an_unknown_profile
    register_librarian

    error = assert_raises(RecordingStudioAgents::ContractError) do
      captured_profile(profile: "turbo")
    end

    assert_match(/low, medium, high/, error.message)
    assert_equal 0, RecordingStudioAgents::AgentRun.count
  end

  private

  def pin_librarian(profile)
    RecordingStudioAgents.agents.register(
      key: :librarian,
      version: 2,
      name: "Librarian",
      description: "Finds pages",
      instructions: "Find the named page.",
      skills: { lookup: 1 },
      tools: { find_page: 1 },
      profile: profile
    )
  end

  def captured_profile(version: 1, **run_options)
    seen = nil
    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      seen = kwargs[:profile]
      generation_response
    }) do
      RecordingStudioAgents.agent(:librarian, version: version).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :web,
        idempotency_key: "profile-#{version}-#{run_options[:profile]}",
        **run_options
      )
    end
    seen
  end
end
