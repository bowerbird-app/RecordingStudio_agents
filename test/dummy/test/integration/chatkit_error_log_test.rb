# frozen_string_literal: true

require "test_helper"

class ChatkitErrorLogTest < ActionDispatch::IntegrationTest
  SECRET = "super-secret-value"
  ErrorLog = RecordingStudioAgents::ChatKit::ErrorLog

  setup do
    @user = User.create!(email: "chatkit-log-#{SecureRandom.hex(4)}@example.com", password: "Password") { |user|
      user.skip_confirmation!
    }
    @root = RecordingStudio.create_root_recording!(Workspace.create!(name: "Log #{SecureRandom.hex(4)}"), actor: @user)
    @other_root = RecordingStudio.create_root_recording!(
      Workspace.create!(name: "Other #{SecureRandom.hex(4)}"), actor: @user
    )
    grant_edit(@user, @root)
    grant_edit(@user, @other_root)
    @configuration = RecordingStudioAgents.configuration
    @previous_actor = @configuration.request_actor
    @previous_root = @configuration.request_root
    @previous_tools = @configuration.mcp_tools
    @configuration.request_actor = ->(*) { @user }
    @configuration.request_root = ->(*) { @root }
    @configuration.mcp_tools = :off
    @lines = []
    @previous_logger = Rails.logger
    Rails.logger = memory_logger(@previous_logger, @lines)
  end

  teardown do
    Rails.logger = @previous_logger if @previous_logger
    Thread.current[ErrorLog::TYPE_KEY] = nil
    next unless @configuration

    @configuration.request_actor = @previous_actor
    @configuration.request_root = @previous_root
    @configuration.mcp_tools = @previous_tools
  end

  test "out of credits stays a 400 and the log names the contract error" do
    with_singleton(RecordingStudioAI::Agents, :create_session, lambda { |**|
      raise RecordingStudioAI::Errors::ContractValidationError.new(
        "Not enough credits for this call.", code: "invalid_request"
      )
    }) do
      post "/recording_studio_agents/chatkit", params: create_payload("hello"), as: :json
    end

    assert_response :bad_request
    assert_equal(
      {
        "type" => "error", "code" => "custom",
        "message" => "Not enough credits for this call.", "allow_retry" => false
      },
      JSON.parse(response.body)
    )
    assert_chatkit_line(
      "chatkit_controller.create",
      "RecordingStudioAI::Errors::ContractValidationError",
      "code=invalid_request",
      "Not enough credits for this call.",
      "type=threads.create"
    )
    refute_chatkit_secret
  end

  test "an authorization contract error stays forbidden" do
    with_singleton(RecordingStudioAI::Agents, :create_session, lambda { |**|
      raise RecordingStudioAI::Errors::ContractValidationError.new(
        "Not authorized for action recording_studio_ai.execute", code: "authorization"
      )
    }) do
      post "/recording_studio_agents/chatkit", params: create_payload("hello"), as: :json
    end

    assert_response :forbidden
    assert_equal "Not authorized for action recording_studio_ai.execute", JSON.parse(response.body).fetch("message")
    assert_chatkit_line("chatkit_controller.create", "code=authorization", "type=threads.create")
  end

  test "a missing page stays a 404 protocol error" do
    post "/recording_studio_agents/chatkit?page_recording_id=not-a-page",
         params: create_payload("hello"), as: :json

    assert_response :not_found
    assert_equal "page was not found", JSON.parse(response.body).fetch("message")
    assert_chatkit_line(
      "chatkit_controller.create", "RecordingStudioAgents::ChatKit::ProtocolError",
      "page was not found", "type=threads.create"
    )
    refute_chatkit_secret
  end

  test "a signed out request stays 401 and is not a warning" do
    @configuration.request_actor = ->(*) { nil }

    post "/recording_studio_agents/chatkit", params: create_payload("hello"), as: :json

    assert_response :unauthorized
    assert_equal "sign in is required", JSON.parse(response.body).fetch("message")
    assert_empty chatkit_lines
  end

  test "invalid json stays invalid request and the body stays out of the log" do
    post "/recording_studio_agents/chatkit",
         params: SECRET, headers: { "CONTENT_TYPE" => "text/plain" }

    assert_response :bad_request
    assert_equal "invalid request", JSON.parse(response.body).fetch("message")
    assert_chatkit_line("server.call", "JSON::ParserError")
    refute_chatkit_secret
  end

  test "bad page context stays a protocol error and logs the parser error" do
    post "/recording_studio_agents/chatkit",
         params: create_payload("hello"),
         headers: { "X-Recording-Studio-Agents-Page" => "{#{SECRET}" },
         as: :json

    assert_response :bad_request
    assert_equal "page context must be an object", JSON.parse(response.body).fetch("message")
    assert_chatkit_line("page_context.parse", "JSON::ParserError")
    assert_chatkit_line(
      "chatkit_controller.create", "RecordingStudioAgents::ChatKit::ProtocolError",
      "page context must be an object", "type=threads.create"
    )
    refute_chatkit_secret
  end

  test "an unusable page id is ignored and logged" do
    page = @other_root.record(Page, actor: @user) { |record| record.title = "Elsewhere" }
    stub_agents
    header = { "page_recording_id" => page.id, "note" => SECRET }.to_json

    post "/recording_studio_agents/chatkit",
         params: create_payload("hello"),
         headers: { "X-Recording-Studio-Agents-Page" => header },
         as: :json

    assert_response :success
    assert_includes response.body, "thread.created"
    assert_chatkit_line("page_context.page_for", "RecordingStudioAgents::ChatKit::ProtocolError", "page was not found")
    refute_chatkit_secret
  ensure
    restore_agents
  end

  test "a recording outside the root stays chat was not found" do
    page = @other_root.record(Page, actor: @user) { |record| record.title = "Elsewhere" }

    result = RecordingStudioAgents::ChatKit::Server.call(
      create_payload("hello").to_json, actor: @user, root_recording: @root, page_recording: page
    )

    assert_equal 404, result.status
    assert_equal "chat was not found", result.body[:message]
    assert_chatkit_line(
      "server.call", "RecordingStudioAgents::IsolationError",
      "recording is outside this root", "type=threads.create"
    )
    refute_includes chatkit_text, "chat was not found"
  end

  test "an actor without access stays forbidden" do
    stranger = User.create!(email: "stranger-#{SecureRandom.hex(4)}@example.com", password: "Password") { |user|
      user.skip_confirmation!
    }

    result = RecordingStudioAgents::ChatKit::Server.call(
      create_payload("hello").to_json, actor: stranger, root_recording: @root
    )

    assert_equal 403, result.status
    assert_equal "actor cannot access this recording", result.body[:message]
    assert_chatkit_line(
      "server.call", "RecordingStudioAgents::Sessions::AccessDeniedError",
      "actor cannot access this recording", "type=threads.create"
    )
  end

  test "a model failure stays an error event" do
    events = []
    provider_failure = failure("model down")
    play(provider_failure) { |event| events << event }

    assert_equal [{ type: "error", code: "custom", message: "model down", allow_retry: true }], events
    assert_chatkit_line("model_stream.play", "RecordingStudioAI::Agents::Failure", "model down")
  end

  test "an unsettled contract error still raises from the model stream" do
    error = contract_error("Not enough credits for this call.", "invalid_request")

    raised = assert_raises(RecordingStudioAI::Errors::ContractValidationError) { play(error) }

    assert_equal "Not enough credits for this call.", raised.message
    assert_equal "invalid_request", raised.code
    assert_chatkit_line(
      "model_stream.play", "code=invalid_request", "Not enough credits for this call."
    )
  end

  test "a settled contract error still ends the model stream" do
    error = contract_error("tool result call_id was already submitted: settled", "invalid_request")

    result = play(error)

    assert_empty result.tool_calls
    assert_chatkit_line("model_stream.play", "code=invalid_request", "already submitted")
  end

  test "cancel swallows a provider error and logs it" do
    stream = model_stream
    with_singleton(RecordingStudioAI::Agents, :cancel, ->(**) { raise RuntimeError, "cancel failed" }) do
      assert_nil stream.cancel!
    end

    assert_chatkit_line("model_stream.cancel", "RuntimeError", "cancel failed")
  end

  test "a failed recovery stays empty and is logged" do
    stream = model_stream
    recover_failure = failure("recover failed")
    with_singleton(RecordingStudioAI::Agents, :recover, ->(**) { raise recover_failure }) do
      assert_nil stream.send(:recovered_session)
    end

    assert_chatkit_line("model_stream.recovered_session", "RecordingStudioAI::Agents::Failure", "recover failed")
  end

  test "a client disconnect is info and still cancels" do
    [IOError.new("closed stream"), ActionController::Live::ClientDisconnected.new("gone")].each do |error|
      @lines.clear
      cancelled = false
      turn = Object.new
      turn.define_singleton_method(:each) { raise error }
      turn.define_singleton_method(:cancel!) { cancelled = true }
      result = RecordingStudioAgents::ChatKit::Result.stream(turn)

      with_singleton(RecordingStudioAgents::ChatKit::Server, :call, ->(*_args, **_kwargs) { result }) do
        post "/recording_studio_agents/chatkit", params: create_payload("hello"), as: :json
      end

      assert cancelled
      assert_includes response.media_type.to_s, "text/event-stream"
      refute_includes response.body, "Not enough credits"
      line = assert_chatkit_line("chatkit_controller.stream_result", error.class.name, "type=threads.create")
      assert_equal :info, line.first
      refute_chatkit_secret
    end
  end

  test "tool delivery logs a timeout and still continues" do
    continued = false
    round = tool_round
    timed_out = timeout_failure
    empty = recovery([])
    with_singleton(RecordingStudioAI::Agents, :submit_tool_results, ->(**) { raise timed_out }) do
      with_singleton(RecordingStudioAI::Agents, :recover, ->(**) { empty }) do
        with_singleton(RecordingStudioAI::Agents, :stream, lambda { |**|
          continued = true
          "continued"
        }) do
          assert_equal "continued", round.send(:deliver, [tool_result])
        end
      end
    end

    assert continued
    assert_chatkit_line("tool_round.deliver", "RecordingStudioAI::Agents::Failure", "Provider request timed out.")
  end

  test "tool delivery still raises a provider failure" do
    round = tool_round
    provider_failure = failure("model down")
    with_singleton(RecordingStudioAI::Agents, :submit_tool_results, ->(**) { raise provider_failure }) do
      assert_raises(RecordingStudioAI::Agents::Failure) { round.send(:deliver, [tool_result]) }
    end

    assert_chatkit_line("tool_round.deliver", "RecordingStudioAI::Agents::Failure", "model down")
  end

  test "a settled tool result still ends the round" do
    round = tool_round
    error = contract_error("tool result call_id was already submitted: settled", "invalid_request")
    with_singleton(RecordingStudioAI::Agents, :submit_tool_results, ->(**) { raise error }) do
      assert_empty round.send(:deliver, [tool_result]).tool_calls
    end

    assert_chatkit_line("tool_round.deliver", "code=invalid_request", "already submitted")
  end

  test "an unsettled tool result still raises" do
    round = tool_round
    error = contract_error("tool result turn_id does not match", "invalid_request")
    with_singleton(RecordingStudioAI::Agents, :submit_tool_results, ->(**) { raise error }) do
      raised = assert_raises(RecordingStudioAI::Errors::ContractValidationError) do
        round.send(:deliver, [tool_result])
      end
      assert_equal "tool result turn_id does not match", raised.message
    end

    assert_chatkit_line("tool_round.deliver", "code=invalid_request", "does not match")
  end

  test "a contract error on the tool retry is logged and the original timeout still decides" do
    round = tool_round
    test = self
    calls = [tool_call, nil]
    error = contract_error("unknown tool result call_id leftover", "invalid_request")
    timed_out = timeout_failure
    with_singleton(RecordingStudioAI::Agents, :recover, lambda { |**|
      test.send(:recovery, Array(calls.shift))
    }) do
      with_singleton(RecordingStudioAI::Agents, :submit_tool_results, ->(**) { raise error }) do
        with_singleton(RecordingStudioAI::Agents, :stream, ->(**) { "continued" }) do
          assert_equal "continued", round.send(:retry_post, [tool_result], timed_out)
        end
      end
    end

    assert_chatkit_line("tool_round.retry_post", "code=invalid_request", "unknown tool result call_id leftover")
  end

  test "a failed tool retry reread still raises the timeout" do
    round = tool_round
    reread_failure = failure("reread failed")
    timed_out = timeout_failure
    with_singleton(RecordingStudioAI::Agents, :recover, ->(**) { raise reread_failure }) do
      raised = assert_raises(RecordingStudioAI::Agents::Failure) do
        round.send(:retry_post, [tool_result], timed_out)
      end
      assert_equal "Provider request timed out.", raised.message
    end

    assert_chatkit_line("tool_round.reread_pending", "RecordingStudioAI::Agents::Failure", "reread failed")
  end

  test "a failed tool cancel stays nil" do
    round = tool_round
    cancel_failure = failure("cancel no")
    with_singleton(RecordingStudioAI::Agents, :cancel, ->(**) { raise cancel_failure }) do
      assert_nil round.send(:cancel_run)
    end

    assert_chatkit_line("tool_round.cancel_run", "RecordingStudioAI::Agents::Failure", "cancel no")
  end

  private

  def create_payload(text)
    {
      type: "threads.create",
      params: {
        input: { content: [{ type: "input_text", text: text }] },
        note: SECRET
      }
    }
  end

  def memory_logger(inner, lines)
    logger = Object.new
    logger.define_singleton_method(:warn) do |message = nil, &block|
      lines << [:warn, (message || block&.call).to_s]
      inner.warn(message, &block)
    end
    logger.define_singleton_method(:info) do |message = nil, &block|
      lines << [:info, (message || block&.call).to_s]
      inner.info(message, &block)
    end
    logger.define_singleton_method(:method_missing) { |name, *args, **kwargs, &block|
      inner.public_send(name, *args, **kwargs, &block)
    }
    logger.define_singleton_method(:respond_to_missing?) { |name, include_private = false|
      inner.respond_to?(name, include_private)
    }
    logger
  end

  def chatkit_lines
    @lines.select { |_level, text| text.include?("[recording_studio_agents.chatkit]") }
  end

  def chatkit_text
    chatkit_lines.map(&:last).join("\n")
  end

  def assert_chatkit_line(*needles)
    line = chatkit_lines.find { |_level, text| needles.all? { |needle| text.include?(needle) } }
    assert line, "expected #{needles.inspect} in #{chatkit_text.inspect}"
    assert_includes line.last, "[recording_studio_agents.chatkit]"
    line
  end

  def refute_chatkit_secret
    refute_includes chatkit_text, SECRET
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

  def with_singleton(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
  end

  def stub_agents
    @agent_methods = {}
    helper = self
    {
      create_session: ->(**) { helper.send(:hosted) },
      send_input: ->(**kwargs) { kwargs.fetch(:session) },
      stream: lambda { |**, &block|
        block&.call(RecordingStudioAI::Providers::StreamEvent.new(type: "message_completed", text: "Saved reply"))
        block&.call(RecordingStudioAI::Providers::StreamEvent.new(type: "turn_completed"))
        helper.send(:hosted)
      },
      recover: ->(**) { helper.send(:recovery, []) },
      cancel: ->(**kwargs) { kwargs[:session] },
      submit_tool_results: ->(**kwargs) { kwargs[:session] }
    }.each do |name, implementation|
      @agent_methods[name] = RecordingStudioAI::Agents.method(name)
      RecordingStudioAI::Agents.define_singleton_method(name, &implementation)
    end
  end

  def restore_agents
    return if @agent_methods.nil?

    @agent_methods.each do |name, original|
      RecordingStudioAI::Agents.define_singleton_method(name) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end

  def model_stream
    recording = Struct.new(:id).new(SecureRandom.uuid)
    stream = RecordingStudioAgents::ChatKit::ModelStream.new(@user, @root, recording)
    stream.define_singleton_method(:agent_args) { { session: "sess" } }
    stream
  end

  def play(error, &block)
    stream = model_stream
    with_singleton(RecordingStudioAI::Agents, :stream, ->(**) { raise error }) do
      stream.play(&block)
    end
  end

  def tool_round
    RecordingStudioAgents::ChatKit::ToolRound.new(actor: @user, root: @root, agent_args: { session: "sess" })
  end

  def tool_call
    RecordingStudioAI::Agents::ToolCall.new(
      call_id: "call_1", name: "show", arguments: { "id" => "1" }, provider_turn_id: "turn_1"
    )
  end

  def tool_result
    { call_id: "call_1", turn_id: "turn_1", output: "ok" }
  end

  def recovery(calls)
    RecordingStudioAI::Agents::Recovery.new(session: "sess", turn: nil, items: [], tool_calls: calls)
  end

  def hosted
    RecordingStudioAI::Agents::Session.new(
      provider: :openai, provider_session_id: "sess_log", model: "demo", profile: "medium", status: "in_progress"
    )
  end

  def failure(message)
    RecordingStudioAI::Agents::Failure.new(
      RecordingStudioAI::Contracts::NormalizedError.new(
        category: "provider_error", code: "bad", message: message, retryable: false
      )
    )
  end

  def timeout_failure
    RecordingStudioAI::Agents::Failure.new(
      RecordingStudioAI::Contracts::NormalizedError.new(
        category: "timeout", code: "timeout", message: "Provider request timed out.", retryable: true
      )
    )
  end

  def contract_error(message, code)
    RecordingStudioAI::Errors::ContractValidationError.new(message, code: code)
  end
end
