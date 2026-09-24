# frozen_string_literal: true

require "test_helper"

class ListPagesToolTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "list-pages-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @workspace = Workspace.create!(name: "List Pages #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @other = RecordingStudio.root_recording_for(Workspace.create!(name: "Other Pages #{SecureRandom.hex(4)}"))
  end

  test "lists titles in this workspace and the folder when a page sits in one" do
    previous = Current.actor
    Current.actor = @user
    folder = record_folder(@root, "Guides")
    record_page(@root, "Welcome", parent: @root)
    record_page(@root, "Start here", parent: folder)
    record_page(@other, "Elsewhere", parent: @other)

    result = RecordingStudioAI.tools.fetch(:list_pages, version: 1).executor.call({}, context_for(@root))

    assert_equal [
      { "title" => "Start here", "folder" => "Guides" },
      { "title" => "Welcome" }
    ], result["pages"]
  ensure
    Current.actor = previous
  end

  test "returns no pages when the workspace has none" do
    result = RecordingStudioAI.tools.fetch(:list_pages, version: 1).executor.call({}, context_for(@root))

    assert_equal({ "pages" => [] }, result)
  end

  private

  def context_for(root)
    Struct.new(:root_recording).new(root)
  end

  def record_folder(root, name)
    RecordingStudio.record!(
      action: "created",
      recordable: Folder.new(name: name),
      root_recording: root,
      parent_recording: root
    ).recording
  end

  def record_page(root, title, parent:)
    RecordingStudio.record!(
      action: "created",
      recordable: Page.new(title: title),
      root_recording: root,
      parent_recording: parent
    ).recording
  end
end
