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
    assert_equal :none, configuration.instructions_override
    assert_equal 4000, configuration.max_instructions_length
    assert_equal :medium, configuration.default_profile
    assert_equal "agent_chat", configuration.purpose
    assert_equal "openai", configuration.provider
    assert_equal 30.days, configuration.retention_period
    assert_equal({}, configuration.chatkit_options)
    assert_nil configuration.layout
    assert_instance_of RecordingStudio::Hooks, configuration.hooks
  end

  def test_provider_is_stripped_and_downcased
    @configuration.provider = " OpenAI "

    assert_equal "openai", @configuration.provider
  end

  def test_a_blank_provider_is_nil
    @configuration.provider = "  "

    assert_nil @configuration.provider
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

  def test_instructions_override_accepts_admin_and_edit
    @configuration.instructions_override = "edit"
    assert_equal :edit, @configuration.instructions_override

    @configuration.merge!(instructions_override: "admin")
    assert_equal :admin, @configuration.instructions_override
    assert_equal :admin, @configuration.to_h.fetch(:instructions_override)
  end

  def test_instructions_override_rejects_an_unknown_gate
    @configuration.instructions_override = :edit

    error = assert_raises(RecordingStudioAgents::Error) { @configuration.instructions_override = :owner }

    assert_equal :edit, @configuration.instructions_override
    assert_match "instructions_override", error.message
  end

  def test_max_instructions_length_accepts_a_numeric_string
    @configuration.max_instructions_length = "20"

    assert_equal 20, @configuration.max_instructions_length
    assert_equal 20, @configuration.to_h.fetch(:max_instructions_length)
  end

  def test_max_instructions_length_rejects_a_non_positive_value
    error = assert_raises(RecordingStudioAgents::Error) { @configuration.max_instructions_length = 0 }

    assert_equal 4000, @configuration.max_instructions_length
    assert_match "positive", error.message
  end

  def test_layout_stores_nil_a_name_false_and_a_keyword_callable
    @configuration.layout = "admin"
    assert_equal "admin", @configuration.layout

    @configuration.layout = nil
    assert_nil @configuration.layout

    @configuration.layout = false
    assert_equal false, @configuration.layout

    callable = ->(controller:) { controller.class.name }
    @configuration.layout = callable
    assert_equal callable, @configuration.layout

    @configuration.merge!(layout: "application")
    assert_equal "application", @configuration.layout
  end

  def test_layout_rejects_values_recording_studio_will_not_accept
    assert_raises(ArgumentError) { @configuration.layout = 1 }
    assert_raises(ArgumentError) { @configuration.layout = "" }
    assert_raises(ArgumentError) { @configuration.layout = ->(controller) { controller.class.name } }

    assert_nil @configuration.layout
  end

  def test_configure_without_block_is_safe
    RecordingStudioAgents.configure

    assert_kind_of RecordingStudioAgents::Configuration, RecordingStudioAgents.configuration
  end
end
