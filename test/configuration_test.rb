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
    assert_equal :write, configuration.mcp_tools
    assert_equal 3, configuration.mcp_max_writes_per_turn
    assert_nil configuration.mcp_tool_allow
    assert_nil configuration.mcp_tool_deny
    assert_equal "tailwind", configuration.popup_stylesheet
    assert_equal "rounded", configuration.popup_theme
    assert_equal true, configuration.launcher
    assert_equal :chat, configuration.launcher_icon
    assert_equal "Open chat", configuration.launcher_label
    assert_equal "Chat", configuration.popup_title
    assert_equal "Chat", configuration.popup_document_title
    assert_equal false, configuration.allow_chat_tools_in_transaction
    assert_equal 10.minutes, configuration.chat_tool_stale_after
    assert_equal 2.minutes, configuration.chat_tool_deadline
    assert_equal 30.days, configuration.retention_period
    assert_equal({}, configuration.chatkit_options)
    assert_equal(
      RecordingStudioAgents::ChatkitHostSettings::DEFAULT_CHATKIT_ALLOWED_ORIGINS,
      configuration.chatkit_allowed_origins
    )
    assert_equal "/users/sign_in", configuration.sign_in_path
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

  def test_chatkit_allowed_origins_accept_a_comma_separated_list
    @configuration.chatkit_allowed_origins = " https://staging.example ,https://app.example "

    assert_equal ["https://staging.example", "https://app.example"], @configuration.chatkit_allowed_origins
  end

  def test_chatkit_allowed_origins_normalize_like_an_embeddable_origin
    @configuration.chatkit_allowed_origins = "HTTPS://App.Example:443/chat"

    assert_equal ["https://app.example"], @configuration.chatkit_allowed_origins
  end

  def test_chatkit_allowed_origins_reject_a_non_http_value
    error = assert_raises(RecordingStudioAgents::Error) do
      @configuration.chatkit_allowed_origins = "ftp://files.example"
    end

    assert_match "http(s) origins", error.message
    assert_equal(
      RecordingStudioAgents::ChatkitHostSettings::DEFAULT_CHATKIT_ALLOWED_ORIGINS,
      @configuration.chatkit_allowed_origins
    )
  end

  def test_frame_ancestor_defaults_are_local_only
    development = with_rails_env("development") { RecordingStudioAgents::Configuration.new.chatkit_allowed_origins }
    test_env = with_rails_env("test") { RecordingStudioAgents::Configuration.new.chatkit_allowed_origins }
    production = with_rails_env("production") { RecordingStudioAgents::Configuration.new.chatkit_allowed_origins }

    local = RecordingStudioAgents::ChatkitHostSettings::DEFAULT_CHATKIT_ALLOWED_ORIGINS
    assert_equal local, development
    assert_equal local, test_env
    assert_empty production
  end

  def with_rails_env(name, &)
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new(name), &)
  end

  def test_sign_in_path_accepts_a_string_or_a_lambda
    @configuration.sign_in_path = "/login"
    assert_equal "/login", @configuration.sign_in_path

    callable = ->(controller) { controller }
    @configuration.sign_in_path = callable
    assert_equal callable, @configuration.sign_in_path

    @configuration.sign_in_path = nil
    assert_equal "/users/sign_in", @configuration.sign_in_path
  end

  def test_mcp_tools_accepts_write_read_and_off
    @configuration.mcp_tools = "read"
    assert_equal :read, @configuration.mcp_tools

    @configuration.merge!(mcp_tools: "off")
    assert_equal :off, @configuration.mcp_tools
    assert_equal :off, @configuration.to_h.fetch(:mcp_tools)
  end

  def test_launcher_accepts_true_false_or_a_lambda
    @configuration.launcher = false
    assert_equal false, @configuration.launcher

    callable = ->(controller) { controller }
    @configuration.launcher = callable
    assert_equal callable, @configuration.launcher

    @configuration.merge!(launcher: true)
    assert_equal true, @configuration.launcher

    error = assert_raises(RecordingStudioAgents::Error) { @configuration.launcher = "yes" }

    assert_equal true, @configuration.launcher
    assert_match "launcher", error.message
    assert_raises(RecordingStudioAgents::Error) { @configuration.launcher = nil }
    assert_raises(RecordingStudioAgents::Error) { @configuration.launcher = 1 }
    assert_equal true, @configuration.launcher
  end

  def test_mcp_max_writes_per_turn_accepts_a_positive_integer
    @configuration.mcp_max_writes_per_turn = "4"
    assert_equal 4, @configuration.mcp_max_writes_per_turn
    assert_equal 4, @configuration.to_h.fetch(:mcp_max_writes_per_turn)

    error = assert_raises(RecordingStudioAgents::Error) { @configuration.mcp_max_writes_per_turn = 0 }

    assert_equal 4, @configuration.mcp_max_writes_per_turn
    assert_match "mcp_max_writes_per_turn", error.message
    assert_raises(RecordingStudioAgents::Error) { @configuration.mcp_max_writes_per_turn = -1 }
    assert_raises(RecordingStudioAgents::Error) { @configuration.mcp_max_writes_per_turn = "no" }
    assert_raises(RecordingStudioAgents::Error) { @configuration.mcp_max_writes_per_turn = 1.5 }
    assert_equal 4, @configuration.mcp_max_writes_per_turn
  end

  def test_mcp_tool_lists_accept_tool_names_and_nil
    @configuration.mcp_tool_allow = ["show", :update, "show"]
    @configuration.mcp_tool_deny = ["create"]

    assert_equal %w[show update], @configuration.mcp_tool_allow
    assert_equal ["create"], @configuration.mcp_tool_deny
    assert_equal ["create"], @configuration.to_h.fetch(:mcp_tool_deny)

    @configuration.merge!(mcp_tool_allow: nil, mcp_tool_deny: [])
    assert_nil @configuration.mcp_tool_allow
    assert_equal [], @configuration.mcp_tool_deny
  end

  def test_mcp_tool_lists_reject_anything_that_is_not_tool_names
    @configuration.mcp_tool_allow = ["show"]

    error = assert_raises(RecordingStudioAgents::Error) { @configuration.mcp_tool_allow = "show" }
    assert_match "mcp_tool_allow", error.message
    assert_equal ["show"], @configuration.mcp_tool_allow
    assert_raises(RecordingStudioAgents::Error) { @configuration.mcp_tool_deny = ["has space"] }
    assert_raises(RecordingStudioAgents::Error) { @configuration.mcp_tool_deny = [1] }
    assert_nil @configuration.mcp_tool_deny
  end

  def test_chat_tool_stale_after_must_be_longer_than_the_deadline
    @configuration.chat_tool_deadline = 30.seconds
    @configuration.chat_tool_stale_after = 90
    assert_equal 90.seconds, @configuration.chat_tool_stale_after
    assert_equal 90.seconds, @configuration.to_h.fetch(:chat_tool_stale_after)

    error = assert_raises(RecordingStudioAgents::Error) { @configuration.chat_tool_stale_after = 20.seconds }
    assert_match "chat_tool_stale_after", error.message
    assert_equal 90.seconds, @configuration.chat_tool_stale_after
    assert_raises(RecordingStudioAgents::Error) { @configuration.chat_tool_stale_after = 60.seconds }
    assert_equal 90.seconds, @configuration.chat_tool_stale_after

    error = assert_raises(RecordingStudioAgents::Error) { @configuration.chat_tool_deadline = 2.minutes }
    assert_match "chat_tool_deadline", error.message
    assert_equal 30.seconds, @configuration.chat_tool_deadline
    assert_raises(RecordingStudioAgents::Error) { @configuration.chat_tool_deadline = 0 }
  end

  def test_mcp_tools_rejects_an_unknown_mode
    error = assert_raises(RecordingStudioAgents::Error) { @configuration.mcp_tools = :ask }

    assert_equal :write, @configuration.mcp_tools
    assert_match "mcp_tools", error.message
  end

  def test_sign_in_path_rejects_a_number
    assert_raises(RecordingStudioAgents::Error) { @configuration.sign_in_path = 1 }

    assert_equal "/users/sign_in", @configuration.sign_in_path
  end

  def test_launcher_chrome_defaults_and_overrides
    assert_equal :chat, @configuration.launcher_icon
    assert_equal "Open chat", @configuration.launcher_label
    assert_equal "Chat", @configuration.popup_title
    assert_equal "Chat", @configuration.to_h.fetch(:popup_title)
    assert_equal :chat, @configuration.to_h.fetch(:launcher_icon)

    @configuration.merge!(launcher_icon: "Sparkles", launcher_label: "Ask", popup_title: "Studio chat")

    assert_equal :sparkles, @configuration.launcher_icon
    assert_equal "Ask", @configuration.launcher_label
    assert_equal "Studio chat", @configuration.popup_title
    assert_equal "Studio chat", @configuration.popup_document_title
  end

  def test_launcher_chrome_rejects_blank_text_and_a_bad_icon
    error = assert_raises(RecordingStudioAgents::Error) { @configuration.launcher_label = "  " }
    assert_match "launcher_label", error.message
    assert_equal "Open chat", @configuration.launcher_label

    error = assert_raises(RecordingStudioAgents::Error) { @configuration.popup_title = " " }
    assert_match "popup_title", error.message
    assert_equal "Chat", @configuration.popup_title

    error = assert_raises(RecordingStudioAgents::Error) { @configuration.launcher_icon = "chat bubble" }
    assert_match "launcher_icon", error.message
    assert_equal :chat, @configuration.launcher_icon
  end

  def test_recording_names_default_to_the_session_title
    assert_equal({ "RecordingStudioAgents::Session" => "title" }, @configuration.recording_names)
    assert_equal @configuration.recording_names, @configuration.to_h.fetch(:recording_names)
  end

  def test_recording_names_accept_a_class_to_field_map
    @configuration.merge!(recording_names: { "Page" => :title, "PressKit" => "name" })

    assert_equal({ "Page" => "title", "PressKit" => "name" }, @configuration.recording_names)
  end

  def test_recording_names_reject_anything_other_than_a_class_and_a_field
    key = assert_raises(RecordingStudioAgents::Error) { @configuration.recording_names = { "page" => "title" } }
    field = assert_raises(RecordingStudioAgents::Error) { @configuration.recording_names = { "Page" => "Title" } }
    shape = assert_raises(RecordingStudioAgents::Error) { @configuration.recording_names = "title" }

    assert_equal "recording_names keys must be recordable class names", key.message
    assert_equal "recording_names values must be field names", field.message
    assert_equal "recording_names must be a hash", shape.message
    assert_equal({ "RecordingStudioAgents::Session" => "title" }, @configuration.recording_names)
  end

  def test_clearing_recording_names_restores_the_default
    @configuration.recording_names = { "Page" => "title" }
    @configuration.recording_names = nil

    assert_equal RecordingStudioAgents::Configuration::DEFAULT_RECORDING_NAMES, @configuration.recording_names
  end
end
