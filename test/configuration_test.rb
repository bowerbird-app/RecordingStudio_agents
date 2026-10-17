# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAgents::Configuration.new
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(instructions: "Be brief.", purpose: "agent_chat", default_profile: "low")

    assert_equal "Be brief.", @configuration.instructions
    assert_equal "agent_chat", @configuration.purpose
    assert_equal :low, @configuration.default_profile
  end

  def test_merge_ignores_unknown_keys
    @configuration.merge!(unknown_key: "ignored", purpose: "support_chat")

    refute_respond_to @configuration, :unknown_key
    assert_equal "support_chat", @configuration.purpose
  end

  def test_merge_with_non_enumerable_is_noop
    original = @configuration.to_h

    @configuration.merge!(nil)

    assert_equal original[:instructions], @configuration.instructions
    assert_equal original[:purpose], @configuration.purpose
    assert_equal original[:retention_period], @configuration.retention_period
  end

  def test_initialize_uses_product_defaults
    configuration = RecordingStudioAgents::Configuration.new

    assert_equal "Answer in plain language.", configuration.instructions
    assert_equal :medium, configuration.default_profile
    assert_equal "agent_chat", configuration.purpose
    assert_equal "openai", configuration.provider
    assert_equal 30.days, configuration.retention_period
    assert_instance_of RecordingStudio::Hooks, configuration.hooks
  end

  def test_retention_period_accepts_a_numeric_second_count
    @configuration.retention_period = 90

    assert_equal 90.seconds, @configuration.retention_period
  end

  def test_merge_accepts_string_keys
    @configuration.merge!("instructions" => "From yaml.", "default_profile" => "high")

    assert_equal "From yaml.", @configuration.instructions
    assert_equal :high, @configuration.default_profile
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
