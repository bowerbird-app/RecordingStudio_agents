# frozen_string_literal: true

require "test_helper"

class ChatkitErrorLogTest < Minitest::Test
  ErrorLog = RecordingStudioAgents::ChatKit::ErrorLog
  Server = RecordingStudioAgents::ChatKit::Server
  SECRET = "super-secret-value"

  def setup
    @previous_logger = Rails.logger
    @lines = []
    lines = @lines
    @logger = Object.new
    @logger.define_singleton_method(:warn) { |message = nil, &block| lines << [:warn, (message || block&.call).to_s] }
    @logger.define_singleton_method(:info) { |message = nil, &block| lines << [:info, (message || block&.call).to_s] }
    Rails.logger = @logger
  end

  def teardown
    Rails.logger = @previous_logger
    Thread.current[ErrorLog::TYPE_KEY] = nil
  end

  def test_warn_line_includes_class_code_message_and_type
    error = RecordingStudioAI::Errors::ContractValidationError.new(
      "Not enough credits for this call.", code: "invalid_request"
    )

    ErrorLog.call(error, site: "chatkit_controller.create", type: "threads.create")

    assert_equal [:warn], @lines.map(&:first)
    assert_equal(
      "[recording_studio_agents.chatkit] chatkit_controller.create " \
      "RecordingStudioAI::Errors::ContractValidationError code=invalid_request " \
      "Not enough credits for this call. type=threads.create",
      @lines.first.last
    )
  end

  def test_line_omits_a_missing_code_and_an_unusable_type
    error = RecordingStudioAgents::Error.new("actor cannot access this recording")

    ErrorLog.call(error, site: "server.call", type: { "note" => SECRET })

    line = @lines.first.last
    assert_equal(
      "[recording_studio_agents.chatkit] server.call RecordingStudioAgents::Error actor cannot access this recording",
      line
    )
    refute_includes line, "code="
    refute_includes line, SECRET
  end

  def test_client_disconnect_is_info
    ErrorLog.call(IOError.new("closed stream"), site: "chatkit_controller.stream_result", level: :info)

    assert_equal [:info], @lines.map(&:first)
    assert_includes @lines.first.last, "chatkit_controller.stream_result"
    assert_includes @lines.first.last, "IOError"
    assert_includes @lines.first.last, "closed stream"
  end

  def test_request_type_from_the_controller_is_used_when_the_site_has_none
    error = RecordingStudioAgents::ChatKit::ProtocolError.new("page was not found", status: 404)

    ErrorLog.with_type("threads.list") do
      ErrorLog.call(error, site: "page_context.page_for")
    end

    assert_includes @lines.first.last, "type=threads.list"
    assert_includes @lines.first.last, "page_context.page_for"
  end

  def test_json_parse_error_drops_the_quoted_source
    error = JSON::ParserError.new("unexpected character: '#{SECRET}' at line 1 column 1")

    ErrorLog.call(error, site: "server.call")

    line = @lines.first.last
    assert_includes line, "JSON::ParserError"
    assert_includes line, "unexpected character: '...' at line 1 column 1"
    refute_includes line, SECRET
  end

  def test_invalid_json_keeps_the_response_and_leaves_the_body_out_of_the_log
    result = Server.call(SECRET, actor: nil, root_recording: nil)

    assert_equal 400, result.status
    assert_equal(
      { type: "error", code: "custom", message: "invalid request", allow_retry: false },
      result.body
    )
    line = @lines.map(&:last).grep(/server\.call/).join("\n")
    assert_includes line, "JSON::ParserError"
    refute_includes line, SECRET
  end

  def test_rejected_instructions_keep_the_response_and_leave_the_body_out_of_the_log
    raw = {
      type: "threads.create",
      params: { instructions: "Be terse.", note: SECRET }
    }.to_json

    result = Server.call(raw, actor: nil, root_recording: nil)

    assert_equal 400, result.status
    assert_equal(
      { type: "error", code: "custom", message: "ChatKit does not accept instructions", allow_retry: false },
      result.body
    )
    line = @lines.map(&:last).join("\n")
    assert_includes line, "server.call"
    assert_includes line, "RecordingStudioAgents::ChatKit::ProtocolError"
    assert_includes line, "ChatKit does not accept instructions"
    assert_includes line, "type=threads.create"
    refute_includes line, SECRET
    refute_includes line, "Be terse."
  end

  def test_a_broken_logger_does_not_raise
    @logger.define_singleton_method(:warn) { |_message| raise "logger down" }

    assert_nil ErrorLog.call(StandardError.new("nope"), site: "server.call")
  end
end
