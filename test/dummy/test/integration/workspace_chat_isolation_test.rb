# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class WorkspaceChatIsolationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "workspace-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @alpha = workspace_root("Alpha")
    @zulu = workspace_root("Zulu")
    grant_edit(@user, @alpha)
    @calls = []
    stub_create
    @alpha_chat = create_chat(@alpha, "alpha hello", "alpha-key")
    @owner = User.create!(email: "owner-#{SecureRandom.hex(4)}@example.com", password: "Password")
    grant_edit(@owner, @zulu)
    @zulu_chat = create_chat(@zulu, "zulu hello", "zulu-key", actor: @owner)
    restore_create
    sign_in @user
  end

  test "switching the selected workspace changes threads.list" do
    grant_edit(@user, @zulu)

    listed = list_threads
    assert_equal [@alpha_chat.id], listed.map { |thread| thread["id"] }

    switch_to(@zulu)
    switched = list_threads

    assert_equal [@zulu_chat.id], switched.map { |thread| thread["id"] }
    refute_includes switched.map { |thread| thread["id"] }, @alpha_chat.id
  end

  test "a user in one workspace cannot list read or append another workspace chat" do
    missing = chatkit("threads.get_by_id", { "thread_id" => @zulu_chat.id })
    refused_append = chatkit("threads.add_user_message", { "thread_id" => @zulu_chat.id, "input" => user_input("nope") })

    assert_equal [@alpha_chat.id], list_threads.map { |thread| thread["id"] }
    assert_equal 404, missing.fetch("http_status")
    assert_equal 404, refused_append.fetch("http_status")

    switch_to(@zulu)

    assert_empty list_threads
    assert_equal 403, chatkit("threads.get_by_id", { "thread_id" => @zulu_chat.id }).fetch("http_status")
    assert_equal 403, chatkit(
      "threads.add_user_message",
      { "thread_id" => @zulu_chat.id, "input" => user_input("nope") }
    ).fetch("http_status")
    assert RecordingStudio::Recording.exists?(@zulu_chat.id)
  end

  private

  def workspace_root(prefix)
    RecordingStudio.root_recording_for(Workspace.create!(name: "#{prefix} #{SecureRandom.hex(4)}"))
  end

  def list_threads
    body = chatkit("threads.list", { "limit" => 20 })
    assert_equal 200, body.fetch("http_status")
    body.fetch("data")
  end

  def chatkit(type, params)
    post "/recording_studio_agents/chatkit", params: { type: type, params: params }, as: :json
    JSON.parse(response.body).merge("http_status" => response.status)
  end

  def switch_to(root)
    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: { root_recording_id: root.id, return_to: "/" }
    }
    assert_response :redirect
  end

  def create_chat(root, input, key, actor: @user)
    RecordingStudioAgents::Sessions::Create.call(
      parent_recording: root, root_recording: root, actor: actor, input: input, idempotency_key: key
    ).value!
  end

  def user_input(text)
    { "content" => [{ "type" => "input_text", "text" => text }] }
  end

  def grant_edit(actor, recording)
    RecordingStudioAccessible::AccessCreationContext.allow do
      recording.record(RecordingStudio::Access, actor: actor, parent_recording: recording) do |access|
        access.actor = actor
        access.role = "edit"
      end
    end
  end

  def stub_create
    @original_create = RecordingStudioAI::Agents.method(:create_session)
    test = self
    RecordingStudioAI::Agents.define_singleton_method(:create_session) do |**kwargs|
      test.instance_variable_get(:@calls) << kwargs
      RecordingStudioAI::Agents::Session.new(
        provider: :openai, provider_session_id: "sess_#{test.instance_variable_get(:@calls).size}",
        model: "gpt-6-astra", profile: "medium", status: "in_progress"
      )
    end
  end

  def restore_create
    original = @original_create
    RecordingStudioAI::Agents.define_singleton_method(:create_session) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
