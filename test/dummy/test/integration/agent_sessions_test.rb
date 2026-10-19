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
    RecordingStudioAgents::Sessions::GlobalKey.reset_index_cache!
  end

  test "create passes a padded provider name as openai" do
    configuration = RecordingStudioAgents.configuration
    previous = configuration.provider
    configuration.provider = " OpenAI "

    create_chat("hello", key: "provider-name")

    assert_equal "openai", @calls[:create_session].first[:provider]
  ensure
    configuration.provider = previous if defined?(configuration) && configuration
  end

  test "create stores the configured instructions" do
    recording = create_chat("hello", key: "default-instructions")

    assert_equal "Answer in one sentence.", recording.recordable.instructions
    assert_equal "Answer in one sentence.", @calls[:create_session].first[:instructions]
  end

  test "create stores an instructions override" do
    recording = create_chat("hello", key: "override-instructions", instructions: "Be terse.")

    assert_equal "Be terse.", recording.recordable.instructions
    assert_equal "Be terse.", @calls[:create_session].last[:instructions]
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

  test "bindings and items copy the recording root" do
    recording = create_chat("hello")
    item = RecordingStudioAgents::Item.new(
      id: SecureRandom.uuid, recording: recording, root_recording: @other_root,
      role: "user", text: "copied", status: "done"
    )
    binding_record = RecordingStudioAgents::Binding.new(
      recording: recording, root_recording: @other_root, provider: "openai",
      create_idempotency_key: "copy-root", last_activity_at: Time.current, expires_at: 1.day.from_now
    )

    assert item.valid?
    assert binding_record.valid?
    assert_equal recording.root_recording_id, item.root_recording_id
    assert_equal recording.root_recording_id, binding_record.root_recording_id
  end

  test "create is idempotent inside one root and the same key succeeds in another root" do
    first = create_chat("hello", key: "same-key")
    second = create_chat("hello", key: "same-key")

    assert_equal first, second
    assert_equal 1, @calls[:create_session].size
    assert_equal @root.id, RecordingStudioAgents::Binding.find_by!(recording: first).root_recording_id

    other = RecordingStudioAgents::Sessions::Create.call(
      parent_recording: @other_root, root_recording: @other_root, actor: @user, input: "hello",
      idempotency_key: "same-key"
    ).value!

    assert_equal @other_root, other.root_recording
    refute_equal first, other
    assert_equal 2, @calls[:create_session].size
    assert_equal 2, RecordingStudioAgents::Binding.where(create_idempotency_key: "same-key").count
    assert_idempotency_indexes_are_scoped_to_root
  end

  test "an actor without access is refused and the chat inherits the parent grant" do
    stranger = User.create!(email: "stranger-#{SecureRandom.hex(4)}@example.com", password: "Password")

    assert_raises(RecordingStudioAgents::Sessions::AccessDeniedError) { create_chat("hello", actor: stranger) }
    assert_empty @calls[:create_session]

    recording = create_chat("hello")
    assert_empty access_recordings_for(recording)
    assert RecordingStudioAccessible.authorized?(actor: @user, recording: recording, role: :edit)

    assert_raises(RecordingStudioAgents::Sessions::AccessDeniedError) { append_chat(recording, actor: stranger) }
    assert_raises(RecordingStudioAgents::Sessions::AccessDeniedError) { rename_chat(recording, actor: stranger) }
    assert_raises(RecordingStudioAgents::Sessions::AccessDeniedError) { close(recording, actor: stranger) }
    assert_raises(RecordingStudioAgents::Sessions::AccessDeniedError) { close_id(recording.id, actor: stranger) }
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

  test "the same append key succeeds in a second root and still dedupes inside one root" do
    recording = create_chat("hello")
    other = RecordingStudioAgents::Sessions::Create.call(
      parent_recording: @other_root, root_recording: @other_root, actor: @user, input: "there",
      idempotency_key: "other-chat"
    ).value!

    RecordingStudioAgents::Sessions::Append.call(
      root_recording: @root, recording: recording, actor: @user, input: "again", idempotency_key: "turn-1"
    ).value!
    RecordingStudioAgents::Sessions::Append.call(
      root_recording: @other_root, recording: other, actor: @user, input: "again", idempotency_key: "turn-1"
    ).value!

    assert_equal 2, @calls[:send_input].size
    assert_equal 2, RecordingStudioAgents::Item.where(idempotency_key: "turn-1").count

    assert_raises(RecordingStudioAgents::Error) do
      sibling = create_chat("sibling", key: "sibling")
      RecordingStudioAgents::Sessions::Append.call(
        root_recording: @root, recording: sibling, actor: @user, input: "nope", idempotency_key: "turn-1"
      ).value!
    end
  end

  test "append refuses an item straggler before the provider" do
    recording = create_chat("hello")
    insert_null_root_item("turn-straggler")

    assert_raises(RecordingStudioAgents::IsolationError) do
      RecordingStudioAgents::Sessions::Append.call(
        root_recording: @root, recording: recording, actor: @user, input: "again", idempotency_key: "turn-straggler"
      ).value!
    end
    assert_empty @calls[:send_input]
  end

  test "create refuses a cross-workspace key before it opens a provider session" do
    RecordingStudioAgents::Sessions::Create.call(
      parent_recording: @other_root, root_recording: @other_root, actor: @user, input: "there",
      idempotency_key: "taken-key"
    ).value!
    add_global_binding_index
    RecordingStudioAgents::Sessions::GlobalKey.reset_index_cache!

    assert_raises(RecordingStudioAgents::KeyConflictError) do
      create_chat("hello", key: "taken-key")
    end
    assert_equal 1, @calls[:create_session].size
    assert_empty @calls[:delete_session]
  end

  test "create deletes the provider session when the global unique index rejects the insert" do
    RecordingStudioAgents::Sessions::Create.call(
      parent_recording: @other_root, root_recording: @other_root, actor: @user, input: "there",
      idempotency_key: "fallback-key"
    ).value!
    add_global_binding_index
    opened = @calls[:create_session].size
    deleted = @calls[:delete_session].size

    ActiveRecord::Base.transaction do
      without_binding_precheck do
        assert_raises(RecordingStudioAgents::KeyConflictError) do
          create_chat("hello", key: "fallback-key")
        end
      end
      follow = create_chat("after", key: "after-conflict")
      assert RecordingStudio::Recording.exists?(follow.id)
    end
    assert_equal opened + 2, @calls[:create_session].size
    assert_equal deleted + 1, @calls[:delete_session].size
  end

  test "a stale true index cache does not block a second workspace" do
    create_chat("hello", key: "stale-key")
    RecordingStudioAgents::Sessions::GlobalKey.binding_index_present = true

    other = RecordingStudioAgents::Sessions::Create.call(
      parent_recording: @other_root, root_recording: @other_root, actor: @user, input: "hello",
      idempotency_key: "stale-key"
    ).value!

    assert_equal @other_root, other.root_recording
    assert_equal false, RecordingStudioAgents::Sessions::GlobalKey.binding_index_present
  end

  test "a missing global index stays cached as false" do
    create_chat("hello", key: "cached-one")
    assert_equal false, RecordingStudioAgents::Sessions::GlobalKey.binding_index_present
    connection = RecordingStudioAgents::Binding.connection
    checks = 0
    original = connection.method(:index_exists?)
    singleton = connection.singleton_class
    singleton.define_method(:index_exists?) do |*args, **kwargs|
      checks += 1
      original.call(*args, **kwargs)
    end

    create_chat("again", key: "cached-two")

    assert_equal 0, checks
  ensure
    singleton.remove_method(:index_exists?) if defined?(singleton) && singleton
  end

  test "a same-root create that loses the unique index returns the existing chat" do
    first = create_chat("hello", key: "race-key")
    finder = RecordingStudioAgents::Binding.method(:find_by)
    calls = 0
    singleton = RecordingStudioAgents::Binding.singleton_class
    singleton.define_method(:find_by) do |*args, **kwargs|
      calls += 1
      next nil if calls == 1

      finder.call(*args, **kwargs)
    end

    second = create_chat("hello", key: "race-key")

    assert_equal first, second
    assert_equal 2, @calls[:create_session].size
    assert_equal 1, @calls[:delete_session].size
  ensure
    singleton.remove_method(:find_by) if defined?(singleton) && singleton
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

  test "expire deletes the stored instructions with the chat" do
    recording = create_chat("old", key: "expired-instructions", instructions: "Keep this private")
    session_id = recording.recordable_id
    RecordingStudioAgents::Binding.find_by!(recording: recording).update!(expires_at: 1.minute.ago)

    closed = RecordingStudioAgents::Sessions::Expire.call.value!

    assert_equal [recording.id], closed
    assert_nil RecordingStudio::Recording.find_by(id: recording.id)
    assert_nil RecordingStudioAgents::Session.find_by(id: session_id)
    refute RecordingStudioAgents::Session.exists?(instructions: "Keep this private")
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

  test "expire closes a chat after its creator loses access" do
    creator = User.create!(email: "creator-#{SecureRandom.hex(4)}@example.com", password: "Password")
    grant_edit(creator, @root)
    recording = create_chat("old", key: "lost-access", actor: creator)
    revoke_edit(creator, @root)
    RecordingStudioAgents::Binding.find_by!(recording: recording).update!(expires_at: 1.minute.ago)

    refute RecordingStudioAccessible.authorized?(actor: creator, recording: recording, role: :edit)
    assert_raises(RecordingStudioAgents::Error) { close(recording, actor: creator) }
    assert_empty @calls[:delete_session]

    closed = RecordingStudioAgents::Sessions::Expire.call.value!

    assert_equal [recording.id], closed
    assert_nil RecordingStudio::Recording.find_by(id: recording.id)
    assert_equal "recording_studio_agents", @calls[:delete_session].last[:initiator].id
    assert_equal :system, @calls[:delete_session].last[:initiator_kind]
    refute_equal creator, @calls[:delete_session].last[:initiator]
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

  def assert_idempotency_indexes_are_scoped_to_root
    connection = ActiveRecord::Base.connection
    binding_indexes = connection.indexes(:recording_studio_agents_bindings)
    item_indexes = connection.indexes(:recording_studio_agents_items)

    assert binding_indexes.any? { |index|
      index.unique && index.columns == %w[root_recording_id create_idempotency_key]
    }
    assert item_indexes.any? { |index|
      index.unique && index.columns == %w[root_recording_id idempotency_key]
    }
    refute binding_indexes.any? { |index| index.name == "index_rs_agents_bindings_on_create_key" }
    refute item_indexes.any? { |index| index.name == "index_rs_agents_items_on_idempotency_key" }
  end

  def create_chat(input, key: SecureRandom.uuid, title: nil, actor: @user, instructions: nil)
    RecordingStudioAgents::Sessions::Create.call(
      parent_recording: @root, root_recording: @root, actor: actor, input: input, idempotency_key: key, title: title,
      instructions: instructions
    ).value!
  end

  def append_chat(recording, actor: @user)
    RecordingStudioAgents::Sessions::Append.call(
      root_recording: @root, recording: recording, actor: actor, input: "again", idempotency_key: SecureRandom.uuid
    ).value!
  end

  def insert_null_root_item(key)
    holder = create_chat("holder", key: "holder-#{key}")
    connection = ActiveRecord::Base.connection
    connection.execute("ALTER TABLE recording_studio_agents_items ALTER COLUMN root_recording_id DROP NOT NULL")
    connection.execute(<<~SQL.squish)
      INSERT INTO recording_studio_agents_items (
        id, recording_id, role, text, status, idempotency_key, created_at, root_recording_id
      ) VALUES (
        #{connection.quote(SecureRandom.uuid)}, #{connection.quote(holder.id)}, 'user', 'old', 'done',
        #{connection.quote(key)}, #{connection.quote(Time.current)}, NULL
      )
    SQL
    connection.add_index :recording_studio_agents_items, :idempotency_key,
                          unique: true, where: "idempotency_key IS NOT NULL",
                          name: "index_rs_agents_items_on_idempotency_key"
    RecordingStudioAgents::Sessions::GlobalKey.reset_index_cache!
  end

  def without_binding_precheck
    klass = RecordingStudioAgents::Sessions::Create
    klass.define_method(:reject_global_binding_straggler!) { nil }
    yield
  ensure
    klass.remove_method(:reject_global_binding_straggler!)
  end

  def add_global_binding_index
    ActiveRecord::Base.connection.add_index :recording_studio_agents_bindings, :create_idempotency_key,
                                            unique: true, name: "index_rs_agents_bindings_on_create_key"
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

  def revoke_edit(actor, recording)
    access_recordings_for(recording).each do |access_recording|
      next unless access_recording.recordable.actor == actor

      access_id = access_recording.recordable_id
      access_recording.destroy!
      RecordingStudio::Access.where(id: access_id).delete_all
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
    return if @original_agents.nil?

    @original_agents.each do |name, original|
      RecordingStudioAI::Agents.define_singleton_method(name, original)
    end
  end
end
