# frozen_string_literal: true

require "test_helper"

class AiAttributionTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAI.configuration
    @previous = @configuration.attribution_validator
  end

  def teardown
    @configuration.attribution_validator = @previous
  end

  def test_install_replaces_the_default_validator
    @configuration.attribution_validator = @configuration.method(:validate_recording_attribution!)

    RecordingStudioAgents::AiAttribution.install!

    assert_equal RecordingStudioAgents::AiAttribution.method(:call), @configuration.attribution_validator
  end

  def test_install_leaves_a_host_validator
    custom = ->(**) {}
    @configuration.attribution_validator = custom

    RecordingStudioAgents::AiAttribution.install!

    assert_equal custom, @configuration.attribution_validator
  end
end
