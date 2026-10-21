# frozen_string_literal: true

require "test_helper"

class RecordingStudioTemplateTest < ActiveSupport::TestCase
  test "dummy app loads root switchable config and controller support" do
    assert_equal [ "all_workspaces" ], RecordingStudioRootSwitchable.configuration.scopes.keys
    assert_equal :application_layout, RecordingStudioRootSwitchable.configuration.layout
    assert_includes ApplicationController.ancestors, RecordingStudio::RootSwitchable::ControllerSupport
    assert_includes ApplicationController.ancestors, RecordingStudio::UsesDefaultLayout
  end

  test "dummy app validates recordable declarations" do
    assert RecordingStudio.validate_recordable_declarations!
    assert_equal [ "Workspace", "RecordingStudioUser::People" ], RecordingStudio.root_recordable_types
    assert_equal [ "Workspace", "Folder" ], RecordingStudio.allowed_parent_types_for("Page")
  end

  test "dummy app schema keeps accessible grants and excludes removed core tables" do
    connection = ActiveRecord::Base.connection

    assert connection.column_exists?(:recording_studio_recordings, :root_recording_id)
    assert connection.table_exists?(:recording_studio_accesses)
    assert connection.table_exists?(:recording_studio_access_constraints)
    assert connection.table_exists?(:recording_studio_access_rules)
    refute connection.table_exists?(:recording_studio_access_boundaries)
    refute connection.table_exists?(:recording_studio_device_sessions)
  end

  test "dummy seeds use hierarchy idempotently and restore current actor" do
    Current.actor = nil

    load Rails.root.join("db/seeds.rb").to_s

    workspace = Workspace.find_by!(name: "Studio Workspace")
    accessible_workspace = Workspace.find_by!(name: "Client Workspace")
    private_workspace = Workspace.find_by!(name: "Private Workspace")
    folder = Folder.find_by!(name: "Product Docs")
    page = Page.find_by!(title: "Getting Started")
    root_recording = RecordingStudio::Recording.find_by!(recordable: workspace)
    accessible_root_recording = RecordingStudio::Recording.find_by!(recordable: accessible_workspace)
    private_root_recording = RecordingStudio::Recording.find_by!(recordable: private_workspace)
    folder_recording = RecordingStudio::Recording.find_by!(recordable: folder)
    page_recording = RecordingStudio::Recording.find_by!(recordable: page)

    assert_nil Current.actor
    assert_nil root_recording.parent_recording_id
    assert_nil accessible_root_recording.parent_recording_id
    assert_nil private_root_recording.parent_recording_id
    assert_equal root_recording, folder_recording.parent_recording
    assert_equal root_recording, folder_recording.root_recording
    assert_equal folder_recording, page_recording.parent_recording
    assert_equal root_recording, page_recording.root_recording
    assert_equal 3, Workspace.count
    press_kits = RecordingStudio::Recording.for_root(root_recording.id).where(recordable_type: "PressKit")
    client_kits = RecordingStudio::Recording.for_root(accessible_root_recording.id).where(recordable_type: "PressKit")
    private_kits = RecordingStudio::Recording.for_root(private_root_recording.id).where(recordable_type: "PressKit")
    assert_equal [ "ACUTE HOUSE", "HELLO HOUSE" ], press_kits.map { |recording| recording.recordable.name }.sort
    assert_equal press_kits.map { |recording| recording.recordable.name }.sort, client_kits.map { |recording| recording.recordable.name }.sort
    assert_empty private_kits
    hello = press_kits.find { |recording| recording.recordable.name == "HELLO HOUSE" }
    assert_equal 6, hello.images(per_page: 20).size
    assert_equal "hello-house", hello.recordable.slug
    assert_includes hello.recordable.description, "Victorian shophouse"
    assert_includes hello.recordable.content, "Rose Nolan"
    assert_includes hello.recordable.sections.map { |section| section["kind"] }, "heading"
    facade = hello.images(per_page: 20).find { |image| image.recordable.original_filename == "hello-house-02.jpg" }
    assert_includes facade.recordable.name, "white bricks spelling HELLO"
    assert facade.recordable.file.attached?

    admin = User.find_by!(email: "admin@admin.com")
    Current.actor = admin
    root_recording.revise(hello, actor: admin) { |press_kit| press_kit.name = "HELLO HOUSE renamed" }
    Current.actor = nil

    assert_no_difference -> { User.count } do
      assert_no_difference -> { RecordingStudio::Recording.count } do
        assert_no_difference -> { RecordingStudioAttachable::Attachment.count } do
          load Rails.root.join("db/seeds.rb").to_s
        end
      end
    end
    assert_nil Current.actor
    renamed = RecordingStudio::Recording.for_root(root_recording.id).where(recordable_type: "PressKit")
    assert_equal [ "ACUTE HOUSE", "HELLO HOUSE renamed" ], renamed.map { |recording| recording.recordable.name }.sort
    kept = renamed.find { |recording| recording.recordable.slug == "hello-house" }
    assert_equal "hello-house", kept.recordable.slug

    stale = kept.images(per_page: 20).find { |image| image.recordable.original_filename == "hello-house-02.jpg" }
    blob_id = stale.recordable.file.blob.id
    Current.actor = admin
    root_recording.revise(stale, actor: admin) do |attachment|
      attachment.name = "filename only"
      attachment.alt_text = "Edited in the app"
      attachment.file.attach(stale.recordable.file.blob)
    end

    assert_no_difference -> { RecordingStudioAttachable::Attachment.count } do
      load Rails.root.join("db/seeds.rb").to_s
    end
    kept_photo = RecordingStudio::Recording.find(stale.id)
    assert_equal "filename only", kept_photo.recordable.name
    assert_equal "Edited in the app", kept_photo.recordable.alt_text
    assert_equal blob_id, kept_photo.recordable.file.blob.id

    Current.actor = admin
    blank_alt = root_recording.revise(kept_photo, actor: admin) do |attachment|
      attachment.alt_text = ""
      attachment.file.attach(kept_photo.recordable.file.blob)
    end

    load Rails.root.join("db/seeds.rb").to_s
    repaired = RecordingStudio::Recording.find(blank_alt.id)
    assert_equal "filename only", repaired.recordable.name
    assert_includes repaired.recordable.alt_text, "white bricks spelling HELLO"
    assert repaired.recordable.file.attached?
    assert_equal blob_id, repaired.recordable.file.blob.id

    assert_no_difference -> { RecordingStudioAttachable::Attachment.count } do
      load Rails.root.join("db/seeds.rb").to_s
    end
  ensure
    Current.actor = nil
  end

  test "workspace opts into accessible and the example mixin without enabling them globally" do
    workspace_source = File.read(Rails.root.join("app/models/workspace.rb"))
    example_source = File.read(RecordingStudioAgents::Engine.root.join("lib/recording_studio_agents/capabilities/example.rb"))

    assert_includes workspace_source, "include RecordingStudio::Capabilities::Example.to(label: \"dummy workspace\")"
    assert_includes example_source, "RecordingStudio::Capabilities.include_for(:example, **)"
    refute_includes example_source, "enable_capability"
    refute_includes example_source, "set_capability_options"

    assert RecordingStudio.capability_enabled?(:accessible, for: Workspace)
    assert RecordingStudio.capability_enabled?(:agents, for: Workspace)
    assert RecordingStudio.capability_enabled?(:example, for: Workspace)
    assert_equal({ label: "dummy workspace" }, RecordingStudio.capability_options(:example, for: Workspace))
    refute RecordingStudio.capability_enabled?(:accessible, for: Folder)
    refute RecordingStudio.capability_enabled?(:accessible, for: Page)
    refute RecordingStudio.capability_enabled?(:example, for: Folder)
    refute RecordingStudio.capability_enabled?(:example, for: Page)
    refute RecordingStudio.capability_enabled?(:agents, for: Folder)
    assert RecordingStudio.capability_enabled?(:agents, for: Page)
    assert_equal [ "Workspace" ], RecordingStudio.configuration.enabled_recordable_types_for(:example)
    assert_includes ApplicationController.ancestors, RecordingStudio::UsesDefaultLayout
  end
end
