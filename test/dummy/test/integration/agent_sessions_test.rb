# frozen_string_literal: true

require "test_helper"

class AgentSessionsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = User.create!(email: "agent-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @root = RecordingStudio.root_recording_for(Workspace.create!(name: "Agent #{SecureRandom.hex(4)}"))
    @other_root = RecordingStudio.root_recording_for(Workspace.create!(name: "Other #{SecureRandom.hex(4)}"))
    grant_edit(@user, @root)
    grant_edit(@user, @other_root)
    @calls = Hash.new { |calls, name| calls[name] = [] }
    @provider_error = nil
    stub_agents
  end

  teardown do
    restore_agents
  end

  test "create records a chat binding and user item" do
    recording = create_chat("hello")

    assert_equal "RecordingStudioAgents::Session", recording.recordable_type
    assert_equal "active", recording.recordable.status
    assert_equal "gpt-6-astra", recording.recordable.model
    assert_equal @root, recording.root_recording
    assert_equal 1, RecordingStudioAgents::Item.where(recording: recording, role: "user").count
    binding_record = RecordingStudioAgents::Binding.find_by!(recording: recording)
    assert_equal "sess_1", binding_record.provider_session_id
    assert_equal 1, @calls[:create_session].size
    assert_equal @root, @calls[:create_session].first[:root_recording]
    assert_equal @root, @calls[:create_session].first[:context_recording]
  end

  test "create is idempotent inside one root and isolated across roots" do
    first = create_chat("hello", key: "same-key")
    second = create_chat("hello", key: "same-key")

    assert_equal first, second
    assert_equal 1, @calls[:create_session].size

    error = assert_raises(RecordingStudioAgents::IsolationError) do
      RecordingStudioAgents::Sessions::Create.call(
        parent_recording: @other_root, root_recording: @other_root, actor: @user, input: "hello",
        idempotency_key: "same-key"
      ).value!
    end

    assert_match(/outside this root/, error.message)
    assert_equal 1, @calls[:create_session].size
  end

  test "an actor without access is refused and the chat inherits the parent grant" do
    stranger = User.create!(email: "stranger-#{SecureRandom.hex(4)}@example.com", password: "Password")

    assert_raises(RecordingStudioAgents::Error) { create_chat("hello", actor: stranger) }
    assert_empty @calls[:create_session]

    recording = create_chat("hello")
    assert_empty access_recordings_for(recording)
    assert RecordingStudioAccessible.authorized?(actor: @user, recording: recording, role: :edit)

    assert_raises(RecordingStudioAgents::Error) { append_chat(recording, actor: stranger) }
    assert_raises(RecordingStudioAgents::Error) { rename_chat(recording, actor: stranger) }
    assert_raises(RecordingStudioAgents::Error) { close(recording, actor: stranger) }
    assert_raises(RecordingStudioAgents::Error) { close_id(recording.id, actor: stranger) }
    assert_empty @calls[:send_input]
    assert_empty @calls[:delete_session]
    assert RecordingStudio::Recording.exists?(recording.id)
  end

  test "a folder cannot parent a chat" do
    folder = @root.record(Folder, actor: @user) { |record| record.name = "Notes" }

    assert_raises(RecordingStudioAgents::Error) do
      RecordingStudioAgents::Sessions::Create.call(
        parent_recording: folder, root_recording: @root, actor: @user, input: "hello",
        idempotency_key: "folder-key"
      ).value!
    end
    assert_empty @calls[:create_session]
  end

  test "append refreshes expiry and does not send a repeated key" do
    recording = create_chat("hello")
    original_expiry = RecordingStudioAgents::Binding.find_by!(recording: recording).expires_at

    travel 2.days do
      RecordingStudioAgents::Sessions::Append.call(
        root_recording: @root, recording: recording, actor: @user, input: "again", idempotency_key: "turn-1"
      ).value!
      RecordingStudioAgents::Sessions::Append.call(
        root_recording: @root, recording: recording, actor: @user, input: "again", idempotency_key: "turn-1"
      ).value!
    end

    assert_equal 1, @calls[:send_input].size
    assert_equal recording, @calls[:send_input].first[:context_recording]
    assert_operator RecordingStudioAgents::Binding.find_by!(recording: recording).expires_at, :>, original_expiry
    assert_equal 1, RecordingStudioAgents::Item.where(idempotency_key: "turn-1").count
  end

  test "append refuses a chat from another root before sending" do
    recording = create_chat("hello")

    assert_raises(RecordingStudioAgents::IsolationError) do
      RecordingStudioAgents::Sessions::Append.call(
        root_recording: @other_root, recording: recording, actor: @user, input: "nope", idempotency_key: "turn-x"
      ).value!
    end
    assert_empty @calls[:send_input]
  end

  test "rename revises the title and keeps the previous snapshot" do
    recording = create_chat("hello", title: "Draft")
    previous_id = recording.recordable_id

    renamed = RecordingStudioAgents::Sessions::Rename.call(
      root_recording: @root, recording: recording, actor: @user, title: "Launch plan"
    ).value!

    assert_equal "Launch plan", renamed.recordable.title
    assert RecordingStudioAgents::Session.exists?(previous_id)
    assert_empty @calls[:send_input]
    assert_empty @calls[:delete_session]
  end

  test "close deletes the provider session and a second close is a no-op" do
    recording = create_chat("hello")
    recording_id = recording.id

    assert_equal recording_id, close(recording)
    assert_equal 1, @calls[:delete_session].size
    assert_nil RecordingStudio::Recording.find_by(id: recording_id)
    assert_equal 0, RecordingStudioAgents::Binding.where(recording_id: recording_id).count
    assert_equal 0, RecordingStudioAgents::Item.where(recording_id: recording_id).count

    assert_nil close_id(recording_id)
    assert_equal 1, @calls[:delete_session].size
  end

  test "close treats an already gone provider session as success" do
    recording = create_chat("hello")
    @provider_error = agent_failure("invalid_session", "invalid_session")

    assert_equal recording.id, close(recording)
    assert_nil RecordingStudio::Recording.find_by(id: recording.id)
  end

  test "close leaves local rows when the provider delete fails" do
    recording = create_chat("hello")
    @provider_error = agent_failure("provider_error", "http_500")

    assert_raises(RecordingStudioAI::Agents::Failure) { close(recording) }
    assert RecordingStudio::Recording.exists?(recording.id)
    assert RecordingStudioAgents::Binding.exists?(recording_id: recording.id)
  end

  test "close of another root does not delete the provider session" do
    recording = create_chat("hello")

    assert_raises(RecordingStudioAgents::IsolationError) do
      RecordingStudioAgents::Sessions::Close.call(
        root_recording: @other_root, recording: recording, actor: @user
      ).value!
    end
    assert_empty @calls[:delete_session]
    assert RecordingStudio::Recording.exists?(recording.id)

    assert_nil RecordingStudioAgents::Sessions::Close.call(
      root_recording: @other_root, recording_id: recording.id, actor: @user
    ).value!
    assert_empty @calls[:delete_session]
    assert RecordingStudio::Recording.exists?(recording.id)
  end

  test "expire closes only expired chats and a second run is a no-op" do
    expired = create_chat("old", key: "expired-key")
    kept = create_chat("fresh", key: "fresh-key")
    RecordingStudioAgents::Binding.find_by!(recording: expired).update!(expires_at: 1.minute.ago)

    closed = RecordingStudioAgents::Sessions::Expire.call.value!
    assert_equal [expired.id], closed
    assert_nil RecordingStudio::Recording.find_by(id: expired.id)
    assert RecordingStudio::Recording.exists?(kept.id)
    assert_equal 1, @calls[:delete_session].size

    assert_empty RecordingStudioAgents::Sessions::Expire.call.value!
    assert_equal 1, @calls[:delete_session].size
  end

  test "expire continues after one provider failure" do
    first = create_chat("one", key: "one")
    second = create_chat("two", key: "two")
    RecordingStudioAgents::Binding.where(recording: [first, second]).update_all(expires_at: 1.minute.ago)
    @provider_error = lambda { |session|
      agent_failure("provider_error", "http_500") if session.provider_session_id == "sess_1"
    }

    RecordingStudioAgents::Sessions::Expire.call.value!

    assert RecordingStudio::Recording.exists?(first.id)
    assert_nil RecordingStudio::Recording.find_by(id: second.id)
  end

  private

  def create_chat(input, key: SecureRandom.uuid, title: nil, actor: @user)
    RecordingStudioAgents::Sessions::Create.call(
      parent_recording: @root, root_recording: @root, actor: actor, input: input, idempotency_key: key, title: title
    ).value!
  end

  def append_chat(recording, actor: @user)
    RecordingStudioAgents::Sessions::Append.call(
      root_recording: @root, recording: recording, actor: actor, input: "again", idempotency_key: SecureRandom.uuid
    ).value!
  end

  def rename_chat(recording, actor: @user)
    RecordingStudioAgents::Sessions::Rename.call(
      root_recording: @root, recording: recording, actor: actor, title: "Launch plan"
    ).value!
  end

  def close(recording, actor: @user)
    RecordingStudioAgents::Sessions::Close.call(root_recording: @root, recording: recording, actor: actor).value!
  end

  def close_id(recording_id, actor: @user)
    RecordingStudioAgents::Sessions::Close.call(
      root_recording: @root, recording_id: recording_id, actor: actor
    ).value!
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

  def access_recordings_for(recording)
    RecordingStudio::Recording.where(parent_recording_id: recording.id, recordable_type: "RecordingStudio::Access")
  end

  def stub_agents
    @original_agents = {}
    helper = self
    {
      create_session: ->(**kwargs) { helper.send(:record_create, kwargs) },
      send_input: ->(**kwargs) { helper.send(:record_send, kwargs) },
      delete_session: ->(**kwargs) { helper.send(:record_delete, kwargs) }
    }.each do |name, implementation|
      remember_agent(name)
      RecordingStudioAI::Agents.define_singleton_method(name, &implementation)
    end
  end

  def record_create(kwargs)
    @calls[:create_session] << kwargs
    hosted_session("sess_#{@calls[:create_session].size}")
  end

  def record_send(kwargs)
    @calls[:send_input] << kwargs
    kwargs.fetch(:session)
  end

  def record_delete(kwargs)
    @calls[:delete_session] << kwargs
    failure = @provider_error
    failure = failure.call(kwargs.fetch(:session)) if failure.respond_to?(:call)
    raise failure if failure

    kwargs.fetch(:session)
  end

  def hosted_session(provider_session_id)
    RecordingStudioAI::Agents::Session.new(
      provider: :openai, provider_session_id: provider_session_id, model: "gpt-6-astra", profile: "medium",
      status: "in_progress"
    )
  end

  def agent_failure(category, code)
    error = RecordingStudioAI::Contracts::NormalizedError.new(
      category: category, code: code, message: code, retryable: false
    )
    RecordingStudioAI::Agents::Failure.new(error)
  end

  def remember_agent(name)
    @original_agents[name] = RecordingStudioAI::Agents.method(name)
  end

  def restore_agents
    @original_agents.each do |name, original|
      RecordingStudioAI::Agents.define_singleton_method(name) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end
end
