# frozen_string_literal: true

require "test_helper"

class AvailabilityTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAgents.configuration
    @previous = @configuration.enabled
  end

  def teardown
    @configuration.enabled = @previous
  end

  def test_a_callable_is_read_again_on_every_call
    flag = true
    @configuration.enabled = -> { flag }

    assert RecordingStudioAgents::Availability.enabled?
    flag = false
    refute RecordingStudioAgents::Availability.enabled?
    flag = true
    assert RecordingStudioAgents::Availability.enabled?(Object.new)
  end

  def test_a_callable_can_take_the_controller_or_no_argument
    seen = :missing
    @configuration.enabled = lambda { |controller|
      seen = controller
      controller.nil?
    }

    assert RecordingStudioAgents::Availability.enabled?(nil)
    assert_nil seen
    refute RecordingStudioAgents::Availability.enabled?(Object.new)

    @configuration.enabled = -> { true }
    assert RecordingStudioAgents::Availability.enabled?(Object.new)
    assert RecordingStudioAgents::Availability.enabled?
  end

  def test_a_raising_callable_is_off_and_the_log_is_only_the_error_class
    secret = "RS_AGENTS_ENABLED=false token=secret-value"
    error_class = Class.new(RuntimeError)
    @configuration.enabled = ->(*) { raise error_class, secret }
    messages = []
    logger = Object.new
    logger.define_singleton_method(:warn) { |line| messages << line }

    Rails.stub(:logger, logger) do
      refute RecordingStudioAgents::Availability.enabled?(nil)
      refute RecordingStudioAgents::Availability.enabled?(Object.new)
    end

    assert_equal ["#{RecordingStudioAgents::Availability::LOG_LINE} #{error_class}"], messages.uniq
    refute_includes messages.join, secret
    refute_includes messages.join, "false"
  end

  def test_a_logger_failure_still_reports_off
    @configuration.enabled = -> { raise "still off" }
    logger = Object.new
    logger.define_singleton_method(:warn) { raise "logger down" }

    Rails.stub(:logger, logger) do
      refute RecordingStudioAgents::Availability.enabled?
    end
  end
end
