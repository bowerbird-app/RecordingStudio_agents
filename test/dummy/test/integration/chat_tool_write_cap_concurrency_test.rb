# frozen_string_literal: true

require "test_helper"

class ChatToolWriteCapConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    skip "SQLite cannot share a connection across threads" if sqlite?

    @user = User.create!(email: "race-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @root = RecordingStudio.root_recording_for(Workspace.create!(name: "Race #{SecureRandom.hex(4)}"))
    grant_edit(@user, @root)
    @configuration = RecordingStudioAgents.configuration
    @previous_writes = @configuration.mcp_max_writes_per_turn
    @configuration.mcp_max_writes_per_turn = 3
  end

  teardown do
    return if sqlite?

    @configuration.mcp_max_writes_per_turn = @previous_writes if @configuration
    RecordingStudioAgents::ChatToolAudit.where(provider_turn_id: %w[turn-race turn-rounds turn-same]).delete_all
    remove_workspace
  end

  test "two threads cannot both pass the write cap" do
    turn_id = "turn-race"
    original = RecordingStudioAgents::ChatToolAudit.method(:writes_used)
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    RecordingStudioAgents::ChatToolAudit.define_singleton_method(:writes_used) do |id|
      sleep 0.05
      original.call(id)
    end
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**|
      sleep 0.02
      { content: [{ type: "text", text: "tool-body" }], isError: false }
    end

    calls = [
      [write_call("a1", turn_id: turn_id), write_call("a2", turn_id: turn_id)],
      [write_call("b1", turn_id: turn_id), write_call("b2", turn_id: turn_id)]
    ]
    results = in_parallel { |index| budget.answer_round(calls.fetch(index)) }

    assert_equal 3, RecordingStudioAgents::ChatToolAudit.writes_used(turn_id)
    limited = results.flatten.select { |result| result[:error] == "write limit reached" }
    assert_equal 1, limited.size
    kept = RecordingStudioAgents::ChatToolAudit.where(provider_turn_id: turn_id).where.not(outcome: "limited")
    assert_equal ["ok"], kept.pluck(:outcome).uniq
  ensure
    restore_singleton(RecordingStudioAgents::ChatToolAudit, :writes_used, original)
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
  end

  test "two threads with the same call id share one write" do
    turn_id = "turn-same"
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**|
      { content: [{ type: "text", text: "tool-body" }], isError: false }
    end

    results = in_parallel { budget.answer_round([write_call("same-call", turn_id: turn_id)]) }

    assert_equal 1, RecordingStudioAgents::ChatToolAudit.where(provider_turn_id: turn_id).count
    assert_equal 1, RecordingStudioAgents::ChatToolAudit.writes_used(turn_id)
    assert_equal results.fetch(0), results.fetch(1)
    refute results.fetch(0).any? { |result| result[:error].present? }
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
  end

  test "an outer transaction keeps the turn lock until it commits" do
    turn_id = "turn-outer"
    key = Integer(RecordingStudioAgents::ChatKit::TurnLock.advisory_key(turn_id))
    entered = Queue.new
    finish = Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        RecordingStudioAgents::ChatToolAudit.transaction do
          RecordingStudioAgents::ChatKit::TurnLock.with(turn_id) { entered << :inside }
          entered << :after
          finish.pop
        end
      end
    end

    assert_equal :inside, entered.pop
    assert_equal :after, entered.pop
    assert_raises(ActiveRecord::LockWaitTimeout) { take_lock(key) }
    finish << true
    worker.join
    take_lock(key)
  ensure
    finish << true if defined?(finish) && finish
    worker.join if defined?(worker) && worker
  end

  test "the turn lock ends when its own transaction commits" do
    turn_id = "turn-free"
    key = Integer(RecordingStudioAgents::ChatKit::TurnLock.advisory_key(turn_id))

    RecordingStudioAgents::ChatKit::TurnLock.with(turn_id) { }

    assert_equal "", take_lock(key)
  end

  test "a turn lock on another database adapter raises" do
    connection = RecordingStudioAgents::ChatToolAudit.connection
    original = connection.method(:adapter_name)
    connection.define_singleton_method(:adapter_name) { "SQLite" }

    error = assert_raises(RecordingStudioAgents::Error) do
      RecordingStudioAgents::ChatKit::TurnLock.with("turn-adapter") { raise "must not yield" }
    end
    assert_includes error.message, "PostgreSQL"
  ensure
    restore_singleton(connection, :adapter_name, original) if connection
  end

  test "two threads take distinct round numbers for one turn" do
    turn_id = "turn-rounds"
    original = RecordingStudioAgents::ChatToolAudit.method(:rounds_used)
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    RecordingStudioAgents::ChatToolAudit.define_singleton_method(:rounds_used) do |id|
      sleep 0.05
      original.call(id)
    end
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**|
      { content: [{ type: "text", text: "tool-body" }], isError: false }
    end

    in_parallel { |index| budget.answer_round([read_call("r#{index}", turn_id: turn_id)]) }

    rounds = RecordingStudioAgents::ChatToolAudit.where(provider_turn_id: turn_id).pluck(:round_number)
    assert_equal [1, 2], rounds.sort
  ensure
    restore_singleton(RecordingStudioAgents::ChatToolAudit, :rounds_used, original)
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
  end

  private

  def sqlite?
    RecordingStudioAgents::ChatToolAudit.connection.adapter_name.match?(/sqlite/i)
  end

  def budget
    RecordingStudioAgents::ChatKit::WriteBudget.new(@user, @root)
  end

  def remove_workspace
    return if @root.nil?

    ids = RecordingStudio::Recording.where(root_recording_id: @root.id).pluck(:id)
    RecordingStudio::Event.where(recording_id: ids).delete_all
    RecordingStudio::Recording.where(id: ids).where.not(id: @root.id).delete_all
    RecordingStudio::Recording.where(id: @root.id).delete_all
    Workspace.where(id: @root.recordable_id).delete_all
    User.where(id: @user&.id).delete_all
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

  def take_lock(key)
    ActiveRecord::Base.connection_pool.with_connection do
      RecordingStudioAgents::ChatToolAudit.transaction do
        RecordingStudioAgents::ChatToolAudit.connection.execute("SET LOCAL lock_timeout = '250ms'")
        RecordingStudioAgents::ChatToolAudit.connection.select_value("SELECT pg_advisory_xact_lock(#{key})::text")
      end
    end
  end

  def in_parallel
    started = Queue.new
    gate = Queue.new
    threads = Array.new(2) do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          started << true
          gate.pop
          yield index
        end
      end
    end
    2.times { started.pop }
    2.times { gate << true }
    threads.map(&:value)
  end

  def write_call(call_id, turn_id:)
    tool_call(call_id, "update", { "id" => "kit" }, turn_id: turn_id)
  end

  def read_call(call_id, turn_id:)
    tool_call(call_id, "show", { "id" => "kit" }, turn_id: turn_id)
  end

  def tool_call(call_id, name, arguments, turn_id:)
    RecordingStudioAI::Agents::ToolCall.new(
      call_id: call_id, name: name, arguments: arguments, provider_turn_id: turn_id
    )
  end

  def restore_singleton(owner, name, original)
    return if original.nil?

    owner.define_singleton_method(name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
