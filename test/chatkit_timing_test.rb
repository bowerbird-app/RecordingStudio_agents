# frozen_string_literal: true

require "test_helper"

class ChatkitTimingTest < Minitest::Test
  Timing = RecordingStudioAgents::ChatKit::Timing

  def setup
    @previous_logger = Rails.logger
    @lines = []
    lines = @lines
    logger = Object.new
    logger.define_singleton_method(:info) { |message = nil, &block| lines << (message || block&.call).to_s }
    Rails.logger = logger
    Thread.current[Timing::KEY] = nil
  end

  def teardown
    Rails.logger = @previous_logger
    Thread.current[Timing::KEY] = nil
  end

  def test_phase_lines_use_the_prefix_and_leave_out_text
    message = "hello timing phrase"
    Timing.open(type: "threads.create")
    Timing.measure("page_context") { message }
    Timing.measure("create") { nil }
    Timing.wrote({ update: { type: "assistant_message.content_part.text_delta", delta: message } }.to_json)
    Timing.measure("tool", name: "show") { nil }
    Timing.measure("tool", name: "bad name #{message}") { nil }
    Timing.round(2, Timing.mark)
    Timing.finish

    text = @lines.join("\n")
    assert_includes text, "[recording_studio_agents.chatkit] timing phase=page_context"
    assert_includes text, "phase=create"
    assert_match(/phase=page_context q=\d+ db=\d+ ms=\d+/, text)
    assert_match(/phase=round q=\d+ db=\d+ n=2 ms=\d+/, text)
    assert_includes text, "phase=ttft"
    assert_includes text, "phase=tool q=0 db=0 name=show"
    assert_includes text, "phase=tool q=0 db=0 name=unknown"
    assert_includes text, "phase=round q=0 db=0 n=2"
    assert_includes text, "phase=total"
    assert_includes text, "type=threads.create"
    assert_match(/phase=ttft q=\d+ db=\d+ ms=\d+ type=threads.create/, text)
    refute_includes text, message
  end

  def test_a_raised_phase_still_logs_and_ttft_waits_for_a_text_delta
    Timing.open(type: "threads.add_user_message")
    assert_raises(RuntimeError) { Timing.measure("append") { raise "hello timing phrase" } }
    Timing.wrote({ type: "thread.item.done", item: { content: [{ text: "hello timing phrase" }] } }.to_json)
    Timing.finish

    text = @lines.join("\n")
    assert_includes text, "phase=append"
    assert_includes text, "phase=total"
    assert_includes text, "type=threads.add_user_message"
    refute_includes text, "phase=ttft"
    refute_includes text, "hello timing phrase"
  end

  def test_durations_come_from_the_monotonic_clock
    Timing.open(type: "threads.create")
    started = Timing.mark
    sleep 0.01
    elapsed = Timing.elapsed_ms(started)

    assert_operator elapsed, :>=, 5
    assert_operator elapsed, :<, 5_000
    assert_in_delta Process.clock_gettime(Process::CLOCK_MONOTONIC), Timing.clock, 1
  ensure
    Timing.finish
  end

  def test_phase_lines_count_queries_and_skip_schema_and_cached
    require "active_support/notifications"
    Timing.open(type: "threads.list")
    Timing.measure("page_context") do
      ActiveSupport::Notifications.instrument("sql.active_record", name: "SCHEMA", sql: "SELECT 1") { nil }
      ActiveSupport::Notifications.instrument("sql.active_record", name: "Session Load", cached: true, sql: "SELECT 1") { nil }
      ActiveSupport::Notifications.instrument("sql.active_record", name: "Session Load", sql: "SELECT 1") { sleep 0.002 }
    end
    Timing.note_drop
    Timing.finish

    line = @lines.find { |entry| entry.include?("phase=page_context") }
    assert_match(/q=1 db=\d+/, line)
    refute_match(/q=3/, line)
    total = @lines.find { |entry| entry.include?("phase=total") }
    assert_includes total, "dropped=1"
    refute_includes total, "SELECT"
  end
end
