# frozen_string_literal: true

require "test_helper"

class ChatToolsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "tools-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @root = RecordingStudio.root_recording_for(Workspace.create!(name: "Tools #{SecureRandom.hex(4)}"))
    @other = RecordingStudio.root_recording_for(Workspace.create!(name: "Other #{SecureRandom.hex(4)}"))
    grant_edit(@user, @root)
    @configuration = RecordingStudioAgents.configuration
    @previous_tools = @configuration.mcp_tools
    @previous_allow = @configuration.mcp_tool_allow
    @previous_deny = @configuration.mcp_tool_deny
    @previous_writes = @configuration.mcp_max_writes_per_turn
    @api = RecordingStudioApi.configuration
    @previous_rate_limit = @api.rate_limit_api_enabled
    @previous_read_limit = @api.rate_limit_api_read_requests
    @previous_read_period = @api.rate_limit_api_read_period_seconds
    @previous_write_limit = @api.rate_limit_api_write_requests
    @previous_write_period = @api.rate_limit_api_write_period_seconds
  end

  teardown do
    @configuration.mcp_tools = @previous_tools
    @configuration.mcp_tool_allow = @previous_allow
    @configuration.mcp_tool_deny = @previous_deny
    @configuration.mcp_max_writes_per_turn = @previous_writes
    @api.rate_limit_api_enabled = @previous_rate_limit
    @api.rate_limit_api_read_requests = @previous_read_limit
    @api.rate_limit_api_read_period_seconds = @previous_read_period
    @api.rate_limit_api_write_requests = @previous_write_limit
    @api.rate_limit_api_write_period_seconds = @previous_write_period
    RecordingStudioApi::ApiSetting.where(key: "api").delete_all
  end

  test "a permission denied tool call returns an error and does not leak the record" do
    secret = @other.record(PressKit, actor: @user) do |kit|
      kit.name = "SECRET TITLE"
      kit.description = "Hidden brief"
      kit.content = "Do not show this"
    end

    result = invoke("show", { "type" => "PressKit", "id" => secret.id })
    text = result.dig(:content, 0, :text).to_s

    assert result[:isError]
    refute_includes text, "SECRET TITLE"
    refute_includes text, "Hidden brief"
    refute_includes text, "Do not show this"
    log = RecordingStudioMcp::UsageLog.order(:created_at).last
    assert_equal "show", log.subject_name
    assert log.failed
  end

  test "a write tool runs as the signed in user" do
    kit = record_kit("HELLO HOUSE")

    result = invoke("update", { "type" => "PressKit", "id" => kit.id, "name" => "RENAMED" })

    refute result[:isError]
    assert_equal "RENAMED", kit.reload.recordable.name
    event = RecordingStudio::Event.where(recording_id: kit.id).order(created_at: :desc).first
    assert_equal @user, event.actor
    assert_nil event.impersonator
    assert_equal "User", event.metadata["authorized_by_type"]
    assert_equal @user.id, event.metadata["authorized_by_id"]
    log = RecordingStudioMcp::UsageLog.order(:created_at).last
    assert_equal "update", log.subject_name
    assert_equal "tools/call", log.method_name
    refute log.failed
    viewer = User.create!(email: "viewer-#{SecureRandom.hex(4)}@example.com", password: "Password")
    grant_role(viewer, @root, "view")
    refused = RecordingStudioAgents::Mcp::ChatTools.invoke(
      "update", { "type" => "PressKit", "id" => kit.id, "name" => "BLOCKED" },
      actor: viewer, root: @root, call_id: "call-viewer"
    )
    assert refused[:isError]
    assert_equal "RENAMED", kit.reload.recordable.name
    refute_includes refused.dig(:content, 0, :text).to_s, "RENAMED"
  end

  test "api access disabled returns an error and does not change the record" do
    kit = record_kit("HELLO HOUSE")
    RecordingStudioApi::ApiSetting.create!(key: "api", api_access_enabled: false)

    result = invoke("update", { "type" => "PressKit", "id" => kit.id, "name" => "RENAMED" })

    assert result[:isError]
    assert_includes result.dig(:content, 0, :text), "temporarily disabled"
    assert_equal "HELLO HOUSE", kit.reload.recordable.name
  end

  test "a rate limit returns an error and does not run the write again" do
    kit = record_kit("HELLO HOUSE")
    original = RecordingStudioApi::Concerns::RateLimiting.method(:redis_client)
    @api.rate_limit_api_enabled = true
    @api.rate_limit_api_write_requests = 1
    @api.rate_limit_api_write_period_seconds = 60
    redis = FakeRedis.new
    original = RecordingStudioApi::Concerns::RateLimiting.method(:redis_client)
    RecordingStudioApi::Concerns::RateLimiting.define_singleton_method(:redis_client) { redis }

    first = invoke("update", { "type" => "PressKit", "id" => kit.id, "name" => "ONCE" }, call_id: "call-once")
    second = invoke("update", { "type" => "PressKit", "id" => kit.id, "name" => "TWICE" }, call_id: "call-twice")

    refute first[:isError]
    assert second[:isError]
    assert_includes second.dig(:content, 0, :text), "Too many requests"
    assert_equal "ONCE", kit.reload.recordable.name
    assert RecordingStudioMcp::UsageLog.order(:created_at).last.rate_limited
  ensure
    RecordingStudioApi::Concerns::RateLimiting.define_singleton_method(:redis_client) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  test "an unexpected tool error is not swallowed" do
    original = RecordingStudioMcp::Dispatcher.method(:call)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) { |**| raise "dispatcher blew up" }

    error = assert_raises(RuntimeError) { invoke("show", { "type" => "PressKit", "id" => "missing" }) }

    assert_equal "dispatcher blew up", error.message
  ensure
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  test "a database error while checking api access is logged and refuses the call" do
    kit = record_kit("HELLO HOUSE")
    messages = []
    logger = Object.new
    logger.define_singleton_method(:error) { |message| messages << message }
    logger.define_singleton_method(:warn) { |message| messages << message }
    boom = ->(**) { raise ActiveRecord::ConnectionNotEstablished, "db down" }

    previous_logger = Rails.logger
    Rails.logger = logger
    original = RecordingStudioApi::ApiSetting.method(:api_access_enabled?)
    RecordingStudioApi::ApiSetting.define_singleton_method(:api_access_enabled?) { |**| boom.call }
    result = invoke("update", { "type" => "PressKit", "id" => kit.id, "name" => "RENAMED" })

    assert result[:isError]
    assert_includes result.dig(:content, 0, :text), "temporarily disabled"
    assert_equal "HELLO HOUSE", kit.reload.recordable.name
    assert_match "ActiveRecord::ConnectionNotEstablished: db down", messages.join
  ensure
    Rails.logger = previous_logger if previous_logger
    if original
      RecordingStudioApi::ApiSetting.define_singleton_method(:api_access_enabled?) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end

  test "a redis error is logged and follows the fail closed setting" do
    require "redis"
    kit = record_kit("HELLO HOUSE")
    messages = []
    logger = Object.new
    logger.define_singleton_method(:error) { |message| messages << message }
    logger.define_singleton_method(:warn) { |message| messages << message }
    previous_closed = @api.rate_limit_fail_closed
    previous_buckets = @api.rate_limit_fail_closed_buckets
    @api.rate_limit_api_enabled = true
    @api.rate_limit_fail_closed = true
    @api.rate_limit_fail_closed_buckets = ["api_write"]
    redis = Object.new
    redis.define_singleton_method(:eval) { |*| raise ::Redis::BaseError, "redis down" }
    original = RecordingStudioApi::Concerns::RateLimiting.method(:redis_client)
    RecordingStudioApi::Concerns::RateLimiting.define_singleton_method(:redis_client) { redis }

    previous_logger = Rails.logger
    Rails.logger = logger
    result = invoke("update", { "type" => "PressKit", "id" => kit.id, "name" => "RENAMED" })

    assert result[:isError]
    assert_includes result.dig(:content, 0, :text), "Too many requests"
    assert_equal "HELLO HOUSE", kit.reload.recordable.name
    assert_match "Redis::BaseError: redis down", messages.join
  ensure
    Rails.logger = previous_logger if previous_logger
    @api.rate_limit_fail_closed = previous_closed
    @api.rate_limit_fail_closed_buckets = previous_buckets
    RecordingStudioApi::Concerns::RateLimiting.define_singleton_method(:redis_client) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  test "the same call id creates one record and list works in process" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    original = RecordingStudioApi::Concerns::RateLimiting.method(:redis_client)
    RecordingStudioApi::Concerns::RateLimiting.define_singleton_method(:redis_client) { nil }
    arguments = {
      "type" => "PressKit",
      "parent_id" => @root.id,
      "name" => "ONCE",
      "description" => "A shophouse",
      "content" => "The wall"
    }

    assert_difference("PressKit.count", 1) do
      @created = invoke("create", arguments, call_id: "c1")
      @replay = invoke("create", arguments.merge("name" => "TWICE"), call_id: "c1")
    end

    refute @created[:isError]
    refute @replay[:isError]
    assert_equal 1, PressKit.where(name: "ONCE").count
    assert_equal 0, PressKit.where(name: "TWICE").count
    assert_includes @created.dig(:content, 0, :text).to_s, "ONCE"
    assert_includes @replay.dig(:content, 0, :text).to_s, "ONCE"

    listed = invoke("list", { "type" => "PressKit" }, call_id: "c-list")

    refute listed[:isError]
    assert_includes listed.dig(:content, 0, :text).to_s, "ONCE"
  ensure
    Rails.cache = previous_cache if previous_cache
    if original
      RecordingStudioApi::Concerns::RateLimiting.define_singleton_method(:redis_client) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end

  test "the rate limit key uses the api layout for a signed in person" do
    grant = RecordingStudioAgents::Mcp::ChatTools.grant_for(@user, @root)
    period = 60
    identifier = RecordingStudioAgents::Mcp::ChatToolLimit.identifier_for(grant, @user)
    window = Time.current.to_i / period
    key = RecordingStudioApi::RateLimit.key(kind: "api_write", identifier: identifier, window: window, api: "public")

    assert_equal "recording_studio_api:api_write:actor:User:#{@user.id}:#{window}", key
  end

  test "allow and deny apply when tools are listed and when they are called" do
    kit = record_kit("HELLO HOUSE")
    @configuration.mcp_tool_allow = %w[show update]
    @configuration.mcp_tool_deny = ["update"]

    names = tool_names
    assert_includes names, "show"
    refute_includes names, "update"
    refute_includes names, "list"

    refused = invoke("update", { "type" => "PressKit", "id" => kit.id, "name" => "RENAMED" })

    assert refused[:isError]
    assert_includes refused.dig(:content, 0, :text), "tool is not allowed"
    assert_equal "HELLO HOUSE", kit.reload.recordable.name

    shown = invoke("show", { "type" => "PressKit", "id" => kit.id }, call_id: "show-allowed")
    refute shown[:isError]

    @configuration.mcp_tool_allow = nil
    @configuration.mcp_tool_deny = ["show"]
    assert_includes tool_names, "update"
    refute_includes tool_names, "show"

    blocked = invoke("show", { "type" => "PressKit", "id" => kit.id }, call_id: "show-denied")
    assert blocked[:isError]
    assert_includes blocked.dig(:content, 0, :text), "tool is not allowed"
  end

  test "tool output sent back to the model is an untrusted envelope" do
    kit = record_kit("HELLO HOUSE")
    call = RecordingStudioAI::Agents::ToolCall.new(
      call_id: "env-1", name: "show",
      arguments: { "type" => "PressKit", "id" => kit.id }, provider_turn_id: "turn-env"
    )

    answered = RecordingStudioAgents::Mcp::ChatTools.answer(call, actor: @user, root: @root)
    parsed = JSON.parse(answered.fetch(:output))

    assert_equal ["untrusted_tool_output"], parsed.keys
    assert_includes parsed.fetch("untrusted_tool_output"), "HELLO HOUSE"
  end

  test "a chat tool call writes an audit row without argument values" do
    secret = "audit-secret-#{SecureRandom.hex(8)}"
    kit = record_kit("HELLO HOUSE")

    RecordingStudioAgents::ChatToolAudit.with_chat(@root) do
      invoke("update", { "type" => "PressKit", "id" => kit.id, "name" => secret }, call_id: "audit-call")
    end

    row = RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "audit-call")
    assert_equal "User", row.actor_type
    assert_equal @user.id, row.actor_id
    assert_equal @root.id, row.chat_recording_id
    assert_equal "update", row.tool_name
    assert_equal "write", row.kind
    assert_equal %w[type id name], row.argument_keys
    assert_equal "ok", row.outcome
    assert_equal "audit-call", row.call_id
    dumped = row.attributes.values.map(&:to_s).join(" ")
    refute_includes row.argument_keys, secret
    refute_includes dumped, secret

    log = RecordingStudioLogs.registry.log_for(RecordingStudioAgents::ChatToolAudit)
    assert_equal :occurred_at, log.timestamp_column
    assert_nil log.partition_interval
    assert_equal :indefinite, log.declared_retention
    assert_empty RecordingStudioLogs.registry.aggregations_for(log)
  end

  test "one provider turn stores a call id once" do
    entry = RecordingStudioAgents::ChatToolAudit::Entry.new(name: "update", arguments: {}, call_id: "same")
    RecordingStudioAgents::ChatToolAudit.with_turn("turn-unique") do
      RecordingStudioAgents::ChatToolAudit.begin!(entry, actor: @user, kind: "write")
      assert_raises(ActiveRecord::RecordNotUnique) do
        RecordingStudioAgents::ChatToolAudit.transaction(requires_new: true) do
          RecordingStudioAgents::ChatToolAudit.begin!(entry, actor: @user, kind: "write")
        end
      end
    end

    RecordingStudioAgents::ChatToolAudit.with_turn(nil) do
      RecordingStudioAgents::ChatToolAudit.begin!(entry, actor: @user, kind: "write")
      RecordingStudioAgents::ChatToolAudit.begin!(entry, actor: @user, kind: "write")
    end
    assert_equal 2, RecordingStudioAgents::ChatToolAudit.where(provider_turn_id: nil, call_id: "same").count
  end

  test "the fourth write in one turn is refused and a read is still answered" do
    assert_equal 3, @configuration.mcp_max_writes_per_turn
    secret = "write-secret-#{SecureRandom.hex(6)}"
    dispatched = []
    submitted = []
    script = [
      tool_turn([write_call("w3"), write_call("w4", secret), read_call("r2")]),
      tool_turn([])
    ]
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    original_submit = RecordingStudioAI::Agents.method(:submit_tool_results)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**kwargs|
      dispatched << kwargs.fetch(:tool_name)
      { content: [{ type: "text", text: "tool-body" }], isError: false }
    end
    RecordingStudioAI::Agents.define_singleton_method(:submit_tool_results) do |**kwargs, &|
      submitted << kwargs.fetch(:results)
      script.shift
    end

    RecordingStudioAgents::ChatKit::ToolRound.new(
      actor: @user, root: @root, agent_args: { session: "sess" }, chat_recording: @root
    ).run([write_call("w1"), write_call("w2"), read_call("r1")]) { |_event| }

    assert_equal %w[update update show update show], dispatched
    results = submitted.flatten
    limited = results.select { |result| result[:error] == "write limit reached" }
    assert_equal ["w4"], limited.map { |result| result[:call_id] }
    read = results.find { |result| result[:call_id] == "r2" }
    assert_equal "tool-body", JSON.parse(read.fetch(:output)).fetch("untrusted_tool_output")
    row = RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "w4")
    assert_equal @root.id, row.chat_recording_id
    assert_equal "turn_1", row.provider_turn_id
    assert_equal "limited", row.outcome
    assert_equal "write", row.kind
    assert_equal ["id"], row.argument_keys
    refute_includes row.attributes.values.map(&:to_s).join(" "), secret
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
    restore_singleton(RecordingStudioAI::Agents, :submit_tool_results, original_submit)
  end

  test "four writes in one round refuse the fourth and still answer a read" do
    calls = [
      write_call("p1", turn_id: "turn-parallel"), write_call("p2", turn_id: "turn-parallel"),
      write_call("p3", turn_id: "turn-parallel"), write_call("p4", turn_id: "turn-parallel"),
      read_call("pr", turn_id: "turn-parallel")
    ]

    ran = scripted_round(calls)

    assert_equal %w[update update update show], ran.fetch(:dispatched)
    limited = ran.fetch(:submitted).select { |result| result[:error] == "write limit reached" }
    assert_equal ["p4"], limited.map { |result| result[:call_id] }
    assert_equal [1], RecordingStudioAgents::ChatToolAudit.where(provider_turn_id: "turn-parallel").distinct.pluck(:round_number)
    assert_equal "ok", RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "pr").outcome
  end

  test "a resumed turn counts earlier writes and refuses the fourth" do
    turn_id = "turn-resume"
    first = scripted_round([write_call("a1", turn_id: turn_id), write_call("a2", turn_id: turn_id)])
    second = scripted_round([write_call("a3", turn_id: turn_id), write_call("a4", turn_id: turn_id)])

    assert_equal %w[update update], first.fetch(:dispatched)
    assert_equal ["update"], second.fetch(:dispatched)
    limited = second.fetch(:submitted).select { |result| result[:error] == "write limit reached" }
    assert_equal ["a4"], limited.map { |result| result[:call_id] }
    assert_equal "ok", RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "a3").outcome
    assert_equal "turn-resume", RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "a1").provider_turn_id
    assert_equal 2, RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "a4").round_number
    assert_equal 3, RecordingStudioAgents::ChatToolAudit.writes_used(turn_id)
  end

  test "a resumed turn counts earlier rounds and refuses the next one" do
    8.times do |index|
      RecordingStudioAgents::ChatToolAudit.with_turn("turn-rounds") do
        RecordingStudioAgents::ChatToolAudit.with_round(index + 1) do
          RecordingStudioAgents::ChatToolAudit.record!(
            RecordingStudioAgents::ChatToolAudit::Entry.new(
              name: "show", arguments: { "id" => "kit" }, call_id: "prior-#{index}"
            ),
            actor: @user, kind: "read", outcome: "ok"
          )
        end
      end
    end

    ran = scripted_round([read_call("next-round", turn_id: "turn-rounds")])

    assert_empty ran.fetch(:dispatched)
    refusal = ran.fetch(:submitted).find { |result| result[:call_id] == "next-round" }
    assert_equal "too many tool calls", refusal[:error]
  end

  test "a tool call is pending before it runs and stays pending when it crashes" do
    kit = record_kit("HELLO HOUSE")
    seen = nil
    original = RecordingStudioMcp::Dispatcher.method(:call)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**|
      seen = RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "pending-ok").outcome
      { content: [{ type: "text", text: "ok" }], isError: false }
    end
    invoke("show", { "type" => "PressKit", "id" => kit.id }, call_id: "pending-ok")
    assert_equal "pending", seen
    assert_equal "ok", RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "pending-ok").outcome

    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) { |**| raise "dispatcher blew up" }
    assert_raises(RuntimeError) do
      invoke("show", { "type" => "PressKit", "id" => kit.id }, call_id: "pending-crash")
    end
    crashed = RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "pending-crash")
    assert_equal "pending", crashed.outcome
    refute_includes crashed.attributes.values.map(&:to_s).join(" "), "dispatcher blew up"
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original)
  end

  test "an empty allow list blocks every tool" do
    kit = record_kit("HELLO HOUSE")
    @configuration.mcp_tool_allow = []

    assert_nil RecordingStudioAgents::Mcp::ChatTools.definitions(actor: @user, root: @root)
    blocked = invoke("show", { "type" => "PressKit", "id" => kit.id }, call_id: "empty-allow")

    assert blocked[:isError]
    assert_includes blocked.dig(:content, 0, :text), "tool is not allowed"
    assert_equal "HELLO HOUSE", kit.reload.recordable.name
    assert_equal "refused", RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "empty-allow").outcome
  end

  test "stored argument keys drop values and non identifiers" do
    secret = "key-secret-#{SecureRandom.hex(6)}"
    long = "n" * 80
    arguments = { "bad key" => secret, "9nope" => secret, long => secret }
    55.times { |index| arguments["field_#{index}"] = secret }
    original = RecordingStudioMcp::Dispatcher.method(:call)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**|
      { content: [{ type: "text", text: "ok" }], isError: false }
    end

    invoke("update", arguments, call_id: "key-cap")

    row = RecordingStudioAgents::ChatToolAudit.find_by!(call_id: "key-cap")
    assert_equal 50, row.argument_keys.size
    assert_equal "n" * 64, row.argument_keys.first
    refute_includes row.argument_keys, "bad key"
    refute_includes row.argument_keys, "9nope"
    refute_includes row.attributes.values.map(&:to_s).join(" "), secret
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original)
  end

  test "read only mode refuses a write without changing the record" do
    kit = record_kit("HELLO HOUSE")
    @configuration.mcp_tools = :read

    result = invoke("update", { "type" => "PressKit", "id" => kit.id, "name" => "RENAMED" })

    assert result[:isError]
    assert_equal "HELLO HOUSE", kit.reload.recordable.name
    refute_includes result.dig(:content, 0, :text).to_s, "HELLO HOUSE"
  end

  private

  def tool_names
    Array(RecordingStudioAgents::Mcp::ChatTools.definitions(actor: @user, root: @root)).map { |tool| tool[:name] }
  end

  def write_call(call_id, secret = "plain", turn_id: "turn_1")
    tool_call(call_id, "update", { "id" => secret }, turn_id: turn_id)
  end

  def read_call(call_id, turn_id: "turn_1")
    tool_call(call_id, "show", { "id" => "kit" }, turn_id: turn_id)
  end

  def tool_call(call_id, name, arguments, turn_id: "turn_1")
    RecordingStudioAI::Agents::ToolCall.new(
      call_id: call_id, name: name, arguments: arguments, provider_turn_id: turn_id
    )
  end

  def scripted_round(calls)
    dispatched = []
    submitted = []
    script = [tool_turn([])]
    original_dispatch = RecordingStudioMcp::Dispatcher.method(:call)
    original_submit = RecordingStudioAI::Agents.method(:submit_tool_results)
    RecordingStudioMcp::Dispatcher.define_singleton_method(:call) do |**kwargs|
      dispatched << kwargs.fetch(:tool_name)
      { content: [{ type: "text", text: "tool-body" }], isError: false }
    end
    RecordingStudioAI::Agents.define_singleton_method(:submit_tool_results) do |**kwargs, &|
      submitted << kwargs.fetch(:results)
      script.shift || tool_turn([])
    end
    RecordingStudioAgents::ChatKit::ToolRound.new(
      actor: @user, root: @root, agent_args: { session: "sess" }, chat_recording: @root
    ).run(calls) { |_event| }
    { dispatched: dispatched, submitted: submitted.flatten }
  ensure
    restore_singleton(RecordingStudioMcp::Dispatcher, :call, original_dispatch)
    restore_singleton(RecordingStudioAI::Agents, :submit_tool_results, original_submit)
  end

  def tool_turn(calls)
    RecordingStudioAI::Agents::Turn.new(
      provider: :openai, provider_session_id: "sess_tools", model: "demo", status: "requires_action",
      run_id: nil, tool_calls: calls
    )
  end

  def restore_singleton(owner, name, original)
    return if original.nil?

    owner.define_singleton_method(name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  def invoke(name, arguments, call_id: "call-1")
    RecordingStudioAgents::Mcp::ChatTools.invoke(
      name, arguments, actor: @user, root: @root, call_id: call_id
    )
  end

  def record_kit(name)
    @root.record(PressKit, actor: @user) do |kit|
      kit.name = name
      kit.description = "A shophouse"
      kit.content = "The wall"
    end
  end

  def grant_edit(actor, recording)
    grant_role(actor, recording, "edit")
  end

  def grant_role(actor, recording, role)
    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(recording).record(
        RecordingStudio::Access, actor: actor, parent_recording: recording
      ) do |access|
        access.actor = actor
        access.role = role
      end
    end
  end

  class FakeRedis
    def initialize
      @counts = Hash.new(0)
    end

    def eval(_script, keys:, argv:)
      @counts[keys.first] += 1
      [@counts[keys.first], argv.first]
    end
  end
end
