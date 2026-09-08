# frozen_string_literal: true

require "test_helper"

class RootBoundaryTest < Minitest::Test
  FakeRecording = Struct.new(:id, :root_recording_id)

  def test_contains_the_root
    root = FakeRecording.new(1, 1)

    assert RecordingStudioAgents::RootBoundary.contained?(root, root)
  end

  def test_contains_a_child
    root = FakeRecording.new(1, 1)
    child = FakeRecording.new(2, 1)

    assert RecordingStudioAgents::RootBoundary.contained?(child, root)
  end

  def test_rejects_an_outsider
    root = FakeRecording.new(1, 1)
    outsider = FakeRecording.new(9, 2)

    refute RecordingStudioAgents::RootBoundary.contained?(outsider, root)
  end

  def test_rejects_nil
    root = FakeRecording.new(1, 1)

    refute RecordingStudioAgents::RootBoundary.contained?(nil, root)
    refute RecordingStudioAgents::RootBoundary.contained?(root, nil)
  end
end
