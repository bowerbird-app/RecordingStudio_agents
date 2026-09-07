# frozen_string_literal: true

require "test_helper"

class LifecycleTest < Minitest::Test
  def test_allows_failed_to_running
    assert_equal "running", RecordingStudioAgents::Lifecycle.transition!(from: "failed", to: "running")
  end

  def test_rejects_succeeded_to_running
    error = assert_raises(RecordingStudioAgents::InvalidTransition) do
      RecordingStudioAgents::Lifecycle.transition!(from: "succeeded", to: "running")
    end
    assert_match(/cannot move from succeeded to running/, error.message)
  end

  def test_rejects_unknown_status
    error = assert_raises(RecordingStudioAgents::InvalidTransition) do
      RecordingStudioAgents::Lifecycle.transition!(from: "mystery", to: "running")
    end
    assert_match(/unknown status mystery/, error.message)
  end

  def test_terminal_states
    assert RecordingStudioAgents::Lifecycle.terminal?("succeeded")
    assert RecordingStudioAgents::Lifecycle.terminal?("handoff_requested")
    refute RecordingStudioAgents::Lifecycle.terminal?("failed")
    refute RecordingStudioAgents::Lifecycle.terminal?("awaiting_confirmation")
  end
end
