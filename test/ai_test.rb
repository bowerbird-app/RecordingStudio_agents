# frozen_string_literal: true

require "test_helper"

class AiRetainedOutputTest < Minitest::Test
  def test_retained_output_skips_runs_without_attempts
    run = Struct.new(:id, :status).new(41, "completed")

    assert_nil RecordingStudioAgents::Ai.retained_output(ai_run: run, initiator: Object.new)
  end

  def test_retained_output_skips_blank_initiator
    run = Struct.new(:id, :attempts).new(41, [])

    assert_nil RecordingStudioAgents::Ai.retained_output(ai_run: run, initiator: nil)
  end
end
