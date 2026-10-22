# frozen_string_literal: true

require "test_helper"

class ChatkitOptionsTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAgents::Configuration.new
    @configuration.purpose = "agent_chat"
    @controller = Object.new
  end

  def test_a_lambda_receives_the_controller_and_purpose_and_a_call_overrides_it
    seen = nil
    @configuration.chatkit_options = lambda do |controller, purpose|
      seen = [controller, purpose]
      {
        composer: { placeholder: "From config" },
        startScreen: { greeting: "From config" },
        api: { url: "https://evil.example/chatkit" },
        theme: { colorScheme: "dark" }
      }
    end

    options = RecordingStudioAgents::ChatKit::Options.for(
      @controller,
      {
        composer: { placeholder: "Ask about this page" },
        startScreen: {
          prompts: [{ label: "Create a PressKit.", prompt: "Create a PressKit." }]
        },
        header: { title: { text: "Press kit" } },
        history: { enabled: true },
        initialThread: nil
      },
      configuration: @configuration
    )

    assert_equal [@controller, "agent_chat"], seen
    assert_equal "Ask about this page", options.dig("composer", "placeholder")
    assert_equal "From config", options.dig("startScreen", "greeting")
    assert_equal "Create a PressKit.", options.dig("startScreen", "prompts", 0, "label")
    assert_equal "Press kit", options.dig("header", "title", "text")
    assert_equal true, options.dig("history", "enabled")
    assert_nil options["initialThread"]
    assert_equal "dark", options.dig("theme", "colorScheme")
    refute options.key?("api")
  end

  def test_a_one_argument_lambda_receives_only_the_controller
    @configuration.chatkit_options = lambda do |controller|
      { header: { title: { text: controller.object_id.to_s } } }
    end

    options = RecordingStudioAgents::ChatKit::Options.for(@controller, nil, configuration: @configuration)

    assert_equal @controller.object_id.to_s, options.dig("header", "title", "text")
  end

  def test_a_zero_argument_lambda_is_called_with_no_arguments
    @configuration.chatkit_options = lambda do
      { composer: { placeholder: "From nowhere" } }
    end

    options = RecordingStudioAgents::ChatKit::Options.for(@controller, nil, configuration: @configuration)

    assert_equal "From nowhere", options.dig("composer", "placeholder")
  end

  def test_a_three_argument_lambda_is_rejected
    error = assert_raises(RecordingStudioAgents::Error) do
      @configuration.chatkit_options = lambda do |_controller, _purpose, _extra|
        {}
      end
    end

    assert_equal "chatkit_options lambda accepts 0, 1, or 2 arguments", error.message
  end

  def test_chatkit_options_rejects_a_string
    error = assert_raises(RecordingStudioAgents::Error) { @configuration.chatkit_options = "nope" }

    assert_equal "chatkit_options must be a hash or a lambda", error.message
  end
end
