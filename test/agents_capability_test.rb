# frozen_string_literal: true

require "test_helper"

class AgentsCapabilityTest < Minitest::Test
  def test_agents_capability_owns_the_session_recordable
    children = RecordingStudio.capability_child_recordables_for(:agents)

    assert_includes children, "RecordingStudioAgents::Session"
    assert_equal "recording_studio_agents", RecordingStudio.registered_capabilities.dig(:agents, :source)
  end

  def test_agent_chats_queries_direct_session_children
    source = File.read(File.expand_path("../lib/recording_studio/capabilities/agents.rb", __dir__))

    assert_includes source, "def self.to(**)"
    assert_includes source, "RecordingStudio::Capabilities.include_for(:agents, **)"
    assert_includes source, "def agent_chats"
    refute_includes source, "enable_capability"
  end
end
