# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAgents::Configuration.new
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(lease_seconds: 120)

    assert_equal 120, @configuration.lease_seconds
  end

  def test_merge_ignores_unknown_keys
    @configuration.merge!(unknown_key: "ignored", lease_seconds: 90)

    refute_respond_to @configuration, :unknown_key
    assert_equal 90, @configuration.lease_seconds
  end

  def test_merge_with_non_enumerable_is_noop
    original = @configuration.to_h

    @configuration.merge!(nil)

    assert_equal original[:lease_seconds], @configuration.lease_seconds
  end

  def test_initialize_defaults_lease_and_hooks
    configuration = RecordingStudioAgents::Configuration.new

    assert_equal 300, configuration.lease_seconds
    assert_instance_of RecordingStudio::Hooks, configuration.hooks
  end

  def test_merge_accepts_string_keys
    @configuration.merge!("lease_seconds" => 12)

    assert_equal 12, @configuration.lease_seconds
  end

  def test_to_h_reports_registered_hook_counts
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.after_service { nil }

    result = @configuration.to_h

    assert_equal 2, result.fetch(:hooks_registered).fetch(:before_initialize)
    assert_equal 1, result.fetch(:hooks_registered).fetch(:after_service)
  end

  def test_configure_without_block_is_safe
    RecordingStudioAgents.configure

    assert_kind_of RecordingStudioAgents::Configuration, RecordingStudioAgents.configuration
  end
end
