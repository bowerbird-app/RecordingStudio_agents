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
    @api = RecordingStudioApi.configuration
    @previous_rate_limit = @api.rate_limit_api_enabled
    @previous_read_limit = @api.rate_limit_api_read_requests
    @previous_read_period = @api.rate_limit_api_read_period_seconds
    @previous_write_limit = @api.rate_limit_api_write_requests
    @previous_write_period = @api.rate_limit_api_write_period_seconds
  end

  teardown do
    @configuration.mcp_tools = @previous_tools
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

  test "the rate limit key uses the api layout for a signed in person" do
    grant = RecordingStudioAgents::Mcp::ChatTools.grant_for(@user, @root)
    period = 60
    key = RecordingStudioAgents::Mcp::ChatToolLimit.counter_key(grant, "api_write", @user, period)
    window = Time.current.to_i / period

    assert_equal "recording_studio_api:api_write:actor:User:#{@user.id}:#{window}", key
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
