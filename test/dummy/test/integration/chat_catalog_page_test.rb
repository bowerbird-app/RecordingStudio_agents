# frozen_string_literal: true

require "test_helper"

class ChatCatalogPageTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "catalog-#{SecureRandom.hex(4)}@example.com", password: "Password") { |user| user.skip_confirmation! }
    @root = RecordingStudio.create_root_recording!(Workspace.create!(name: "Catalog #{SecureRandom.hex(4)}"), actor: @user)
    grant_edit(@user, @root)
    @catalog = RecordingStudioAgents::ChatKit::Catalog.new(@user, @root)
  end

  test "threads list pages in order and keeps has_more" do
    newest = record_chat("newest", 3.hours.ago)
    middle = record_chat("middle", 2.hours.ago)
    oldest = record_chat("oldest", 1.hour.ago)
    same = record_chat("same", 1.hour.ago)

    first = @catalog.list_threads("limit" => 2)
    second = @catalog.list_threads("limit" => 2, "after" => first[:after])
    ordered = RecordingStudio::Recording.where(id: [newest, middle, oldest, same].map(&:id)).order(created_at: :desc, id: :desc).pluck(:id)

    assert_equal ordered.first(2), first[:data].map { |thread| thread[:id] }
    assert_equal true, first[:has_more]
    assert_equal ordered[2, 2], second[:data].map { |thread| thread[:id] }
    assert_equal false, second[:has_more]
    assert_nil second[:after]
    assert_equal ordered, (first[:data] + second[:data]).map { |thread| thread[:id] }
  end

  test "an unknown after starts at the newest chat" do
    older = record_chat("older", 2.hours.ago)
    newer = record_chat("newer", 1.hour.ago)

    listed = @catalog.list_threads("limit" => 20, "after" => SecureRandom.uuid)

    assert_equal [newer.id, older.id], listed[:data].map { |thread| thread[:id] }
  end

  test "unauthorized rows are skipped without a short page" do
    kept = []
    hidden = []
    6.times do |index|
      chat = record_chat("chat #{index}", index.hours.ago)
      (index < 3 ? hidden : kept) << chat
    end

    with_hidden(hidden.map(&:id)) do
      listed = @catalog.list_threads("limit" => 2)
      assert_equal 2, listed[:data].size
      assert_equal true, listed[:has_more]
      assert_empty listed[:data].map { |thread| thread[:id] } & hidden.map(&:id)
      rest = @catalog.list_threads("limit" => 2, "after" => listed[:after])
      assert_equal 1, rest[:data].size
      assert_equal false, rest[:has_more]
    end
  end

  test "the query count stays flat as the chat count grows" do
    8.times { |index| record_chat("small #{index}", index.minutes.ago) }
    @catalog.list_threads("limit" => 2)
    small = sql_count { @catalog.list_threads("limit" => 2) }
    24.times { |index| record_chat("large #{index}", (index + 10).minutes.ago) }
    statements = []
    large = sql_count { statements = capture_sql { @catalog.list_threads("limit" => 2) } }

    assert_operator small, :>, 0
    assert_operator large, :<=, small + 2
    assert statements.any? { |sql| sql.match?(/LIMIT/i) }
  end

  test "limit 9999 stops at 50 and a page parent stays in the list" do
    page = @root.record(Page, actor: @user) { |record| record.title = "Press kit" }
    page_chat = page.record(RecordingStudioAgents::Session, actor: @user, parent_recording: page) do |chat|
      chat.title = "on the page"
      chat.status = "active"
      chat.model = "demo"
      chat.purpose = "chat"
    end
    record_chat("workspace", 1.hour.ago)
    51.times { |index| record_chat("bulk #{index}", (index + 2).hours.ago) }

    capped = @catalog.list_threads("limit" => 9999)
    scoped = RecordingStudioAgents::ChatKit::Catalog.new(@user, @root, page_recording: page).list_threads("limit" => 20)

    assert_equal 50, capped[:data].size
    assert_equal true, capped[:has_more]
    assert_equal [page_chat.id], scoped[:data].map { |thread| thread[:id] }
    assert_equal page_chat.recordable.title, scoped[:data].first[:title]
  end

  private

  def record_chat(title, created_at)
    recording = @root.record(RecordingStudioAgents::Session, actor: @user) do |chat|
      chat.title = title
      chat.status = "active"
      chat.model = "demo"
      chat.purpose = "chat"
    end
    recording.update_columns(created_at: created_at)
    recording
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

  def with_hidden(ids)
    original = RecordingStudioAccessible.method(:authorized?)
    hidden = Array(ids)
    RecordingStudioAccessible.define_singleton_method(:authorized?) do |*args, **kwargs|
      recording = kwargs[:recording]
      return false if hidden.include?(recording&.id)

      original.call(*args, **kwargs)
    end
    yield
  ensure
    restore_authorized(original)
  end

  def restore_authorized(original)
    return if original.nil?

    RecordingStudioAccessible.define_singleton_method(:authorized?) do |*args, **kwargs|
      original.call(*args, **kwargs)
    end
  end

  def capture_sql
    statements = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql].to_s
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end

  def sql_count
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA"

      count += 1
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    end
    count
  end
end
