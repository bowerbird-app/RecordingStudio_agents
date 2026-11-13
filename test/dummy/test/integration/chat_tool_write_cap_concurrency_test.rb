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
    ids = %w[turn-race turn-rounds turn-same turn-capped turn-posted turn-stale turn-recovered]
    RecordingStudioAgents::ChatToolAudit.where(provider_turn_id: ids).delete_all
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
    dispatches = []
    finishes = []
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    original_finish = RecordingStudioAgents::ChatToolAudit.method(:finish!)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**|
      dispatches << :ran
      sleep 0.05
      { content: [{ type: "text", text: "tool-body" }], isError: false }
    end
    RecordingStudioAgents::ChatToolAudit.define_singleton_method(:finish!) do |row, outcome|
      finishes << outcome.to_s
      original_finish.call(row, outcome)
    end

    results = in_parallel { budget.answer_round([write_call("same-call", turn_id: turn_id)]) }
    row = RecordingStudioAgents::ChatToolAudit.find_by!(provider_turn_id: turn_id, call_id: "same-call")

    assert_equal 1, dispatches.size
    assert_equal ["ok"], finishes
    assert_equal "ok", row.outcome
    assert_equal 1, RecordingStudioAgents::ChatToolAudit.where(provider_turn_id: turn_id).count
    assert_equal 1, RecordingStudioAgents::ChatToolAudit.writes_used(turn_id)
    flat = results.flatten
    assert_equal 1, flat.count { |result| result[:joined] }
    assert_equal 1, flat.count { |result| result[:output].present? }
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
    restore_singleton(RecordingStudioAgents::ChatToolAudit, :finish!, original_finish)
  end

  test "a duplicate call id past the cap keeps the first outcome" do
    turn_id = "turn-capped"
    @configuration.mcp_max_writes_per_turn = 1
    dispatches = []
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**|
      dispatches << :ran
      { content: [{ type: "text", text: "tool-body" }], isError: false }
    end

    budget.answer_round([write_call("kept", turn_id: turn_id)])
    budget.answer_round([write_call("capped", turn_id: turn_id)])
    again = budget.answer_round([write_call("capped", turn_id: turn_id)])
    row = RecordingStudioAgents::ChatToolAudit.find_by!(provider_turn_id: turn_id, call_id: "capped")

    assert_equal "limited", row.outcome
    assert_equal 1, dispatches.size
    assert_equal 1, again.flatten.count { |result| result[:joined] }
    assert_equal 2, RecordingStudioAgents::ChatToolAudit.where(provider_turn_id: turn_id).count
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
  end

  test "a joined call is left out of the posted results" do
    turn_id = "turn-posted"
    dispatches = []
    submitted = []
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    original_submit = RecordingStudioAI::Agents.method(:submit_tool_results)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**|
      dispatches << :ran
      { content: [{ type: "text", text: "tool-body" }], isError: false }
    end
    RecordingStudioAI::Agents.define_singleton_method(:submit_tool_results) do |**kwargs, &|
      submitted << kwargs.fetch(:results)
    end

    events = []
    budget.answer_round([write_call("posted", turn_id: turn_id)])
    RecordingStudioAgents::ChatKit::ToolRound.new(
      actor: @user, root: @root, agent_args: { session: "sess" }
    ).run([write_call("posted", turn_id: turn_id)]) { |event| events << event }
    row = RecordingStudioAgents::ChatToolAudit.find_by!(provider_turn_id: turn_id, call_id: "posted")

    assert_equal 1, dispatches.size
    assert_empty submitted
    assert_equal "ok", row.outcome
    assert_equal "already_handled", events.map(&:type).first
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
    restore_singleton(RecordingStudioAI::Agents, :submit_tool_results, original_submit)
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

  test "an open transaction raises unless the host allows it" do
    previous = @configuration.allow_chat_tools_in_transaction
    @configuration.allow_chat_tools_in_transaction = false

    error = assert_raises(RecordingStudioAgents::Error) do
      RecordingStudioAgents::ChatToolAudit.transaction do
        RecordingStudioAgents::ChatKit::TurnLock.with("turn-host") { raise "must not yield" }
      end
    end
    assert_includes error.message, "open transaction"
  ensure
    @configuration.allow_chat_tools_in_transaction = previous if @configuration
  end

  test "boot rejects a non PostgreSQL database when chat tools are on" do
    config = RecordingStudioAgents::ChatToolAudit.connection_db_config
    original = config.method(:configuration_hash)
    config.define_singleton_method(:configuration_hash) { { adapter: "sqlite3" } }

    error = assert_raises(RecordingStudioAgents::Error) do
      RecordingStudioAgents::ChatKit::TurnLock.check_adapter!
    end
    assert_includes error.message, "PostgreSQL"
  ensure
    restore_singleton(config, :configuration_hash, original) if config
  end

  test "boot skips the database check when there is no database config" do
    original = RecordingStudioAgents::ChatToolAudit.method(:connection_db_config)
    RecordingStudioAgents::ChatToolAudit.define_singleton_method(:connection_db_config) { nil }

    assert_nil RecordingStudioAgents::ChatKit::TurnLock.check_adapter!
  ensure
    restore_singleton(RecordingStudioAgents::ChatToolAudit, :connection_db_config, original)
  end

  test "boot skips the database check when chat tools are off" do
    previous = @configuration.mcp_tools
    @configuration.mcp_tools = :off
    original = RecordingStudioAgents::ChatToolAudit.method(:connection_db_config)
    RecordingStudioAgents::ChatToolAudit.define_singleton_method(:connection_db_config) do
      raise "must not read the database"
    end

    assert_nil RecordingStudioAgents::ChatKit::TurnLock.check_adapter!
  ensure
    @configuration.mcp_tools = previous if @configuration
    restore_singleton(RecordingStudioAgents::ChatToolAudit, :connection_db_config, original)
  end

  test "a stale pending call is posted as unknown and is not re-run" do
    turn_id = "turn-stale"
    dispatches = []
    submitted = []
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    original_submit = RecordingStudioAI::Agents.method(:submit_tool_results)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) { |**| dispatches << :ran }
    RecordingStudioAI::Agents.define_singleton_method(:submit_tool_results) do |**kwargs, &|
      submitted << kwargs.fetch(:results)
      Struct.new(:tool_calls).new([])
    end
    RecordingStudioAgents::ChatToolAudit.create!(
      occurred_at: 3.hours.ago, tool_name: "update", kind: "write", outcome: "pending",
      call_id: "stale", provider_turn_id: turn_id, argument_keys: []
    )

    RecordingStudioAgents::ChatKit::ToolRound.new(
      actor: @user, root: @root, agent_args: { session: "sess" }
    ).run([write_call("stale", turn_id: turn_id)]) { |_event| }
    row = RecordingStudioAgents::ChatToolAudit.find_by!(provider_turn_id: turn_id, call_id: "stale")
    posted = submitted.flatten.first

    assert_empty dispatches
    assert_equal false, posted[:success]
    assert_equal "tool call outcome unknown; it was not re-run", posted[:output]
    assert_equal "pending", row.outcome
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
    restore_singleton(RecordingStudioAI::Agents, :submit_tool_results, original_submit)
  end

  test "a pending call still waiting on recover is posted as unknown" do
    turn_id = "turn-recovered"
    dispatches = []
    submitted = []
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    original_submit = RecordingStudioAI::Agents.method(:submit_tool_results)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) { |**| dispatches << :ran }
    RecordingStudioAI::Agents.define_singleton_method(:submit_tool_results) do |**kwargs, &|
      submitted << kwargs.fetch(:results)
      Struct.new(:tool_calls).new([])
    end
    RecordingStudioAgents::ChatToolAudit.create!(
      occurred_at: Time.current, tool_name: "update", kind: "write", outcome: "pending",
      call_id: "waiting", provider_turn_id: turn_id, argument_keys: []
    )

    RecordingStudioAgents::ChatKit::ToolRound.new(
      actor: @user, root: @root, agent_args: { session: "sess" }, recovered: true
    ).run([write_call("waiting", turn_id: turn_id)]) { |_event| }
    posted = submitted.flatten.first

    assert_empty dispatches
    assert_equal false, posted[:success]
    assert_equal "tool call outcome unknown; it was not re-run", posted[:output]
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
    restore_singleton(RecordingStudioAI::Agents, :submit_tool_results, original_submit)
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
