# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class ChatkitRunsTableTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "runs-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @root = RecordingStudio.root_recording_for(Workspace.create!(name: "Runs #{SecureRandom.hex(4)}"))
    grant_edit(@user, @root)
    sign_in @user
    @configuration = RecordingStudioAgents.configuration
    @previous_actor = @configuration.request_actor
    @previous_root = @configuration.request_root
    @previous_tools = @configuration.mcp_tools
    @configuration.request_actor = ->(*) { @user }
    @configuration.request_root = ->(*) { @root }
    @configuration.mcp_tools = :off
    @ai = RecordingStudioAI.configuration
    @previous_key = @ai.openai_api_key
    @ai.openai_api_key = "sk-test"
    stub_hosted_agent
  end

  teardown do
    restore_hosted_agent
    @configuration.request_actor = @previous_actor
    @configuration.request_root = @previous_root
    @configuration.mcp_tools = @previous_tools
    @ai.openai_api_key = @previous_key
  end

  test "threads.create writes a hosted agent run instead of missing the runs table" do
    before = RecordingStudioAI::Run.count

    post "/recording_studio_agents/chatkit",
         params: {
           type: "threads.create",
           params: { input: { content: [{ type: "input_text", text: "Say hello in one sentence." }] } }
         },
         as: :json

    assert_response :success
    refute_includes response.body, "PG::UndefinedTable"
    refute_includes response.body, "recording_studio_ai_runs"
    assert_equal before + 1, RecordingStudioAI::Run.count
    run = RecordingStudioAI::Run.order(:created_at).last
    assert_equal "hosted_agent", run.operation
    assert_equal @root.id, run.root_recording_id
    assert_includes response.body, "thread.created"
  end

  test "a stream may rebuild the root as an id after the run is stored" do
    attribution = RecordingStudioAI::Contracts::Attribution.new(
      root_recording: @root.id, initiator: @user, execution_source: "web"
    )

    assert_equal @root, attribution.root_recording

    error = assert_raises(RecordingStudioAI::Errors::ContractValidationError) do
      RecordingStudioAI::Contracts::Attribution.new(
        root_recording: SecureRandom.uuid, initiator: @user, execution_source: "web"
      )
    end
    assert_includes error.message, "root_recording must be a Recording Studio root"
  end

  private

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

  def stub_hosted_agent
    @adapter = RecordingStudioAI.configuration.providers.fetch(:openai)
    session = RecordingStudioAI::Providers::HostedSession.new(
      provider_session_id: "sess_test", status: "idle", model: "gpt-5-mini"
    )
    @adapter.define_singleton_method(:create_hosted_agent_session) do |**|
      session
    end
    @adapter.define_singleton_method(:stream_hosted_agent_session) do |**, &block|
      block.call(RecordingStudioAI::Providers::StreamEvent.new(type: "message_completed", text: "Hello."))
      block.call(RecordingStudioAI::Providers::StreamEvent.new(type: "turn_completed"))
    end
  end

  def restore_hosted_agent
    return unless @adapter

    %i[create_hosted_agent_session stream_hosted_agent_session].each do |name|
      @adapter.singleton_class.remove_method(name) if @adapter.singleton_class.method_defined?(name)
    end
  end
end
