# frozen_string_literal: true

require "test_helper"

class OutOfCreditsTest < Minitest::Test
  Usage = RecordingStudioAgents::ChatKit::UsageNotice
  CreditUrl = RecordingStudioAgents::ChatKit::CreditUrl

  def setup
    load_locales
    @configuration = RecordingStudioAgents::Configuration.new
    @global = RecordingStudioAgents.configuration
    @previous_url = @global.out_of_credits_url
    @previous_label = @global.out_of_credits_label
    @global.out_of_credits_url = nil
    @global.out_of_credits_label = nil
  end

  def teardown
    @global.out_of_credits_url = @previous_url
    @global.out_of_credits_label = @previous_label
  end

  def test_a_string_url_and_a_callable_url
    request = Struct.new(:base_url).new("https://studio.test")
    root = Struct.new(:id).new("root-1")
    @configuration.out_of_credits_url = "/billing"

    assert_equal "/billing", @configuration.out_of_credits_url
    href = @configuration.out_of_credits_href(request: request, root_recording: root)

    assert_equal "https://studio.test/billing", href

    seen = nil
    @configuration.out_of_credits_url = lambda { |request:, root_recording:|
      seen = [request.base_url, root_recording.id]
      "https://billing.example/add"
    }

    assert_equal(
      "https://billing.example/add",
      @configuration.out_of_credits_href(request: request, root_recording: root)
    )
    assert_equal ["https://studio.test", "root-1"], seen
  end

  def test_a_nil_url_and_an_unsafe_url
    @configuration.out_of_credits_url = "/billing"
    @configuration.out_of_credits_url = nil

    assert_nil @configuration.out_of_credits_url
    assert_nil @configuration.out_of_credits_href(request: nil, root_recording: nil)

    error = assert_raises(RecordingStudioAgents::Error) { @configuration.out_of_credits_url = "javascript:alert(1)" }

    assert_match "http(s)", error.message
    assert_nil @configuration.out_of_credits_url
    assert_raises(RecordingStudioAgents::Error) { @configuration.out_of_credits_url = "data:text/html,hi" }
    assert_raises(RecordingStudioAgents::Error) { @configuration.out_of_credits_url = "ftp://files.example/x" }
    assert_raises(RecordingStudioAgents::Error) { @configuration.out_of_credits_url = 1 }

    @configuration.out_of_credits_url = lambda { |request:, root_recording:|
      "javascript:alert(#{request}#{root_recording})"
    }
    assert_raises(RecordingStudioAgents::Error) do
      @configuration.out_of_credits_href(request: nil, root_recording: nil)
    end
  end

  def test_the_label_defaults_to_i18n_and_can_be_overridden
    assert_nil @configuration.out_of_credits_label
    assert_equal "Add credits", Usage.action_label

    @global.out_of_credits_label = "Buy credits"
    assert_equal "Buy credits", Usage.action_label

    @global.out_of_credits_label = nil
    I18n.with_locale(:fr) { assert_equal "Ajouter des crédits", Usage.action_label }
    assert_raises(RecordingStudioAgents::Error) { @configuration.out_of_credits_label = " " }
  end

  def test_a_new_thread_streams_the_message_and_the_notice_without_storing_them
    @global.out_of_credits_url = "/billing"
    events = events_for("threads.create", "hello there")

    types = events.map { |event| event["type"] }

    assert_equal %w[thread.created thread.item.done thread.item.done], types
    assert_match(/\A[0-9a-f-]{36}\z/, events.first.dig("thread", "id"))
    assert_equal "hello there", events[1].dig("item", "content", 0, "text")
    assert_equal "user_message", events[1].dig("item", "type")
    notice = events.last.dig("item", "content", 0, "text")
    assert_includes notice, "You're out of AI credits, so this message wasn't sent."
    assert_includes notice, "[Add credits](https://studio.test/billing)"
    assert_equal "assistant_message", events.last.dig("item", "type")
  end

  def test_an_existing_thread_streams_the_notice_on_that_thread
    events = events_for("threads.add_user_message", "again", thread_id: "thread-9")

    types = events.map { |event| event["type"] }

    assert_equal %w[thread.item.done thread.item.done], types
    assert_equal "thread-9", events.first.dig("item", "thread_id")
    assert_equal "again", events.first.dig("item", "content", 0, "text")
    assert_includes events.last.dig("item", "content", 0, "text"), "wasn't sent"
    refute_includes events.last.dig("item", "content", 0, "text"), "]("
  end

  def test_french_copy_and_a_custom_label
    @global.out_of_credits_url = "https://studio.test/credits"
    @global.out_of_credits_label = "Recharger"
    events = I18n.with_locale(:fr) { events_for("threads.create", "bonjour") }
    notice = events.last.dig("item", "content", 0, "text")

    assert_includes notice, "Vous n'avez plus de crédits d'IA, ce message n'a donc pas été envoyé."
    assert_includes notice, "[Recharger](https://studio.test/credits)"
  end

  def test_a_mid_stream_decline_emits_the_notice
    events = []
    recording = Struct.new(:id).new("thread-live")
    stream = RecordingStudioAgents::ChatKit::ModelStream.new(nil, nil, recording)
    stream.define_singleton_method(:agent_args) { { session: "sess" } }
    with_agent(:stream, ->(**) { raise RecordingStudioAI::Errors::UsageDeclined }) do
      stream.play { |event| events << event }
    end

    assert_equal "thread.item.done", events.last[:type]
    assert_equal "assistant_message", events.last.dig(:item, :type)
    assert_equal "thread-live", events.last.dig(:item, :thread_id)
    assert_includes events.last.dig(:item, :content, 0, :text), "wasn't sent"
  end

  def test_another_contract_error_still_raises_from_the_model_stream
    recording = Struct.new(:id).new("thread-live")
    stream = RecordingStudioAgents::ChatKit::ModelStream.new(nil, nil, recording)
    stream.define_singleton_method(:agent_args) { { session: "sess" } }
    error = RecordingStudioAI::Errors::ContractValidationError.new("nope", code: "invalid_request")

    raised = nil
    with_agent(:stream, ->(**) { raise error }) do
      raised = assert_raises(RecordingStudioAI::Errors::ContractValidationError) { stream.play { |_| } }
    end

    assert_equal "invalid_request", raised.code
    refute_kind_of RecordingStudioAI::Errors::UsageDeclined, raised
  end

  def test_a_tool_round_decline_is_logged_and_raised
    round = RecordingStudioAgents::ChatKit::ToolRound.new(actor: nil, root: nil, agent_args: { session: "sess" })

    assert_raises(RecordingStudioAI::Errors::UsageDeclined) do
      with_agent(:submit_tool_results, ->(**) { raise RecordingStudioAI::Errors::UsageDeclined }) do
        round.send(:deliver, [{ call_id: "call_1", turn_id: "turn_1", output: "ok" }])
      end
    end
  end

  private

  def events_for(type, text, thread_id: nil)
    params = { input: { content: [{ type: "input_text", text: text }] } }
    params[:thread_id] = thread_id if thread_id
    raw = { type: type, params: params }.to_json
    request = Struct.new(:base_url).new("https://studio.test")
    Usage.context(request: request, root_recording: Struct.new(:id).new("root-1")) do
      Usage.result(raw).each.map { |json| JSON.parse(json) }
    end
  end

  def with_agent(name, implementation)
    original = RecordingStudioAI::Agents.method(name)
    RecordingStudioAI::Agents.define_singleton_method(name, &implementation)
    yield
  ensure
    RecordingStudioAI::Agents.define_singleton_method(name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  def load_locales
    root = File.expand_path("..", __dir__)
    Dir[File.join(root, "config/locales/*.yml")].each do |path|
      I18n.load_path << path unless I18n.load_path.include?(path)
    end
    I18n.backend.reload!
    I18n.available_locales |= %i[en fr] if I18n.respond_to?(:available_locales=)
  end
end
