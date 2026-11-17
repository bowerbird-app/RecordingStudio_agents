# frozen_string_literal: true

require "test_helper"

class ChatkitOutOfCreditsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "credits-#{SecureRandom.hex(4)}@example.com", password: "Password") { |user|
      user.skip_confirmation!
    }
    @root = RecordingStudio.create_root_recording!(Workspace.create!(name: "Credits #{SecureRandom.hex(4)}"), actor: @user)
    grant_edit(@user, @root)
    @configuration = RecordingStudioAgents.configuration
    @previous_actor = @configuration.request_actor
    @previous_root = @configuration.request_root
    @previous_tools = @configuration.mcp_tools
    @previous_url = @configuration.out_of_credits_url
    @previous_label = @configuration.out_of_credits_label
    @configuration.request_actor = ->(*) { @user }
    @configuration.request_root = ->(*) { @root }
    @configuration.mcp_tools = :off
    @configuration.out_of_credits_url = nil
    @configuration.out_of_credits_label = nil
    @decline = nil
    @lines = []
    @previous_logger = Rails.logger
    Rails.logger = memory_logger(@previous_logger, @lines)
    stub_agents
  end

  teardown do
    restore_agents
    Rails.logger = @previous_logger if @previous_logger
    next unless @configuration

    @configuration.request_actor = @previous_actor
    @configuration.request_root = @previous_root
    @configuration.mcp_tools = @previous_tools
    @configuration.out_of_credits_url = @previous_url
    @configuration.out_of_credits_label = @previous_label
  end

  test "a declined new chat streams the notice and stores nothing" do
    @decline = :create
    @configuration.out_of_credits_url = "/billing"
    before = counts

    post chatkit_path, params: payload("threads.create", "hello there"), as: :json

    assert_response :success
    assert_equal "text/event-stream", response.media_type
    events = sse_events
    assert_equal %w[thread.created thread.item.done thread.item.done], events.map { |event| event["type"] }
    thread_id = events.first.dig("thread", "id")
    assert_match(/\A[0-9a-f-]{36}\z/, thread_id)
    assert_nil RecordingStudio::Recording.find_by(id: thread_id)
    assert_equal "hello there", events[1].dig("item", "content", 0, "text")
    notice = events.last.dig("item", "content", 0, "text")
    assert_includes notice, "You're out of AI credits, so this message wasn't sent."
    assert_includes notice, "[Add credits](http://www.example.com/billing)"
    assert_equal before, counts
    assert_chatkit_line(
      "chatkit_controller.create",
      "RecordingStudioAI::Errors::UsageDeclined",
      "code=usage_declined",
      "type=threads.create"
    )

    post chatkit_path, params: { type: "threads.get_by_id", params: { thread_id: thread_id } }, as: :json

    assert_response :not_found
    listed = chatkit_json("threads.list", {})
    refute_includes listed.fetch("data").map { |thread| thread["id"] }, thread_id
  end

  test "a declined reply on an existing thread is not stored" do
    created = sse_from("threads.create", "hello")
    thread_id = created.first.dig("thread", "id")
    before = counts
    @decline = :append
    @configuration.out_of_credits_url = ->(request:, root_recording:) { "/plans/#{root_recording.id}" }

    events = sse_from("threads.add_user_message", "not sent", thread_id: thread_id)

    assert_equal %w[thread.item.done thread.item.done], events.map { |event| event["type"] }
    assert_equal "not sent", events.first.dig("item", "content", 0, "text")
    assert_equal thread_id, events.first.dig("item", "thread_id")
    assert_includes events.last.dig("item", "content", 0, "text"), "(http://www.example.com/plans/#{@root.id})"
    assert_equal before, counts
    listed = chatkit_json("items.list", { "thread_id" => thread_id })
    texts = listed.fetch("data").map { |item| item.dig("content", 0, "text") }
    assert_includes texts, "hello"
    refute_includes texts, "not sent"
    refute_includes texts.join, "out of AI credits"
  end

  test "a nil url omits the link and the label can be overridden" do
    @decline = :create
    events = sse_from("threads.create", "hello")
    notice = events.last.dig("item", "content", 0, "text")

    assert_equal "You're out of AI credits, so this message wasn't sent.", notice
    refute_includes notice, "Add credits"

    @configuration.out_of_credits_url = "/billing"
    @configuration.out_of_credits_label = "Buy credits"
    events = sse_from("threads.create", "hello again")

    assert_includes events.last.dig("item", "content", 0, "text"), "[Buy credits](http://www.example.com/billing)"
  end

  test "french copy uses the locale strings" do
    @decline = :create
    @configuration.out_of_credits_url = "/billing"
    events = I18n.with_locale(:fr) { sse_from("threads.create", "bonjour") }
    notice = events.last.dig("item", "content", 0, "text")

    assert_includes notice, "Vous n'avez plus de crédits d'IA, ce message n'a donc pas été envoyé."
    assert_includes notice, "[Ajouter des crédits](http://www.example.com/billing)"
  end

  test "an unsafe url is rejected before the stream" do
    @decline = :create
    @configuration.out_of_credits_url = ->(request:, root_recording:) { "javascript:#{request}#{root_recording}" }

    error = assert_raises(RecordingStudioAgents::Error) do
      post chatkit_path, params: payload("threads.create", "hello"), as: :json
    end

    assert_match "http(s)", error.message
    refute_includes error.message, "javascript:"
    assert_chatkit_line("chatkit_controller.create", "code=usage_declined")
  end

  test "a mid-stream decline streams the same notice" do
    @decline = :stream
    @configuration.out_of_credits_url = "/billing"
    before_items = RecordingStudioAgents::Item.count

    events = sse_from("threads.create", "hello")

    assert_includes events.map { |event| event["type"] }, "thread.created"
    assert_equal "hello", events.find { |event| event.dig("item", "type") == "user_message" }.dig("item", "content", 0, "text")
    notice = events.find { |event| event.dig("item", "type") == "assistant_message" }
    assert_includes notice.dig("item", "content", 0, "text"), "[Add credits](http://www.example.com/billing)"
    texts = RecordingStudioAgents::Item.order(:created_at).pluck(:role, :text)
    assert_equal [ [ "user", "hello" ] ], texts.last(1)
    assert_equal before_items + 1, RecordingStudioAgents::Item.count
    refute texts.any? { |_role, text| text.include?("out of AI credits") }
    assert_chatkit_line("model_stream.play", "RecordingStudioAI::Errors::UsageDeclined", "code=usage_declined")
  end

  test "another contract error stays a 400" do
    @decline = :contract

    post chatkit_path, params: payload("threads.create", "hello"), as: :json

    assert_response :bad_request
    assert_equal "application/json", response.media_type
    body = JSON.parse(response.body)
    assert_equal "custom", body.fetch("code")
    assert_equal false, body.fetch("allow_retry")
    assert_equal "Not enough credits for this call.", body.fetch("message")
    assert_chatkit_line("chatkit_controller.create", "code=invalid_request", "type=threads.create")
    refute_includes @lines.map(&:last).join, "code=usage_declined"
  end

  private

  def chatkit_path
    "/recording_studio_agents/chatkit"
  end

  def payload(type, text, thread_id: nil)
    params = { input: { content: [ { type: "input_text", text: text } ], attachments: [], inference_options: {} } }
    params[:thread_id] = thread_id if thread_id
    { type: type, params: params }
  end

  def sse_from(type, text, thread_id: nil)
    post chatkit_path, params: payload(type, text, thread_id: thread_id), as: :json
    assert_response :success
    sse_events
  end

  def sse_events
    response.body.each_line.filter_map do |line|
      next unless line.start_with?("data: ")

      JSON.parse(line.delete_prefix("data: ").strip)
    end
  end

  def chatkit_json(type, params)
    post chatkit_path, params: { type: type, params: params }, as: :json
    assert_response :success
    JSON.parse(response.body)
  end

  def counts
    {
      sessions: RecordingStudioAgents::Session.count,
      items: RecordingStudioAgents::Item.count,
      bindings: RecordingStudioAgents::Binding.count,
      recordings: RecordingStudio::Recording.count
    }
  end

  def grant_edit(actor, recording)
    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(recording).record(
        RecordingStudio::Access, actor: actor, parent_recording: recording
      ) do |access|
        access.actor = actor
        access.role = "edit"
      end
    end
  end

  def stub_agents
    @agent_methods = {}
    helper = self
    implementations = {
      create_session: ->(**kwargs) { helper.send(:scripted_create, kwargs) },
      send_input: ->(**kwargs) { helper.send(:scripted_send, kwargs) },
      stream: ->(**kwargs, &block) { helper.send(:scripted_stream, kwargs, block) },
      recover: ->(**) { helper.send(:scripted_recovery) },
      cancel: ->(**kwargs) { kwargs[:session] },
      delete_session: ->(**kwargs) { kwargs[:session] },
      submit_tool_results: ->(**kwargs) { kwargs[:session] }
    }
    implementations.each do |name, implementation|
      @agent_methods[name] = RecordingStudioAI::Agents.method(name)
      RecordingStudioAI::Agents.define_singleton_method(name, &implementation)
    end
  end

  def scripted_create(_kwargs)
    case @decline
    when :create then raise RecordingStudioAI::Errors::UsageDeclined
    when :contract
      raise RecordingStudioAI::Errors::ContractValidationError.new(
        "Not enough credits for this call.", code: "invalid_request"
      )
    else hosted("sess_#{SecureRandom.hex(2)}")
    end
  end

  def scripted_send(kwargs)
    raise RecordingStudioAI::Errors::UsageDeclined if @decline == :append

    kwargs.fetch(:session)
  end

  def scripted_stream(kwargs, block)
    raise RecordingStudioAI::Errors::UsageDeclined if @decline == :stream

    block&.call(RecordingStudioAI::Providers::StreamEvent.new(type: "message_completed", text: "Saved reply"))
    block&.call(RecordingStudioAI::Providers::StreamEvent.new(type: "turn_completed"))
    kwargs.fetch(:session)
  end

  def scripted_recovery
    RecordingStudioAI::Agents::Recovery.new(session: "sess", turn: nil, items: [], tool_calls: [])
  end

  def hosted(provider_session_id)
    RecordingStudioAI::Agents::Session.new(
      provider: :openai, provider_session_id: provider_session_id, model: "demo", profile: "medium", status: "in_progress"
    )
  end

  def restore_agents
    return if @agent_methods.nil?

    @agent_methods.each do |name, original|
      RecordingStudioAI::Agents.define_singleton_method(name) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end

  def memory_logger(inner, lines)
    logger = Object.new
    %i[warn info].each do |level|
      logger.define_singleton_method(level) do |message = nil, &block|
        lines << [ level, (message || block&.call).to_s ]
        inner.public_send(level, message, &block)
      end
    end
    logger.define_singleton_method(:method_missing) { |name, *args, **kwargs, &block| inner.public_send(name, *args, **kwargs, &block) }
    logger.define_singleton_method(:respond_to_missing?) { |name, include_private = false| inner.respond_to?(name, include_private) }
    logger
  end

  def assert_chatkit_line(*parts)
    text = @lines.map(&:last).join("\n")
    parts.each { |part| assert_includes text, part }
  end
end
