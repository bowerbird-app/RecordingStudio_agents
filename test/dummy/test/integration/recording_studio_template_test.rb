# frozen_string_literal: true

require "test_helper"

class RecordingStudioTemplateTest < ActiveSupport::TestCase
  test "dummy app loads root switchable config and controller support" do
    assert_equal [ "all_workspaces" ], RecordingStudioRootSwitchable.configuration.scopes.keys
    assert_equal :application_layout, RecordingStudioRootSwitchable.configuration.layout
    assert_includes ApplicationController.ancestors, RecordingStudio::RootSwitchable::ControllerSupport
    assert_includes ApplicationController.ancestors, RecordingStudio::UsesDefaultLayout
  end

  test "dummy app validates declarations" do
    assert RecordingStudio.validate_recordable_declarations!
    assert_includes RecordingStudio.root_recordable_types, "Workspace"
    assert_includes RecordingStudio.root_recordable_types, "AdminRoot"
    assert_equal [ "Workspace", "Folder" ], RecordingStudio.allowed_parent_types_for("Page")
  end

  test "dummy app schema keeps agents tables and accessible grants" do
    connection = ActiveRecord::Base.connection

    assert connection.column_exists?(:recording_studio_recordings, :root_recording_id)
    assert connection.table_exists?(:recording_studio_accesses)
    assert connection.table_exists?(:recording_studio_agents_agent_runs)
    assert connection.table_exists?(:admin_roots)
    refute connection.column_exists?(:recording_studio_agents_tasks, :context_json)
    refute connection.table_exists?(:recording_studio_access_boundaries)
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
    assert RecordingStudioAgents::AgentRun.exists?(idempotency_key: "seed:page_librarian")

    assert_no_difference -> { User.count } do
      assert_no_difference -> { RecordingStudio::Recording.count } do
        load Rails.root.join("db/seeds.rb").to_s
      end
    end
    assert_nil Current.actor
  ensure
    Current.actor = nil
  end

  test "workspace and admin root opt into accessible without a template mixin" do
    workspace_source = File.read(Rails.root.join("app/models/workspace.rb"))
    admin_source = File.read(Rails.root.join("app/models/admin_root.rb"))

    assert_includes workspace_source, "enable_capability(:accessible"
    assert_includes admin_source, "enable_capability(:accessible"
    refute_includes workspace_source, "Capabilities::Example"
    refute File.exist?(RecordingStudioAgents::Engine.root.join("lib/recording_studio_agents/capabilities/example.rb"))

    assert RecordingStudio.capability_enabled?(:accessible, for: Workspace)
    assert RecordingStudio.capability_enabled?(:accessible, for: AdminRoot)
    refute RecordingStudio.capability_enabled?(:accessible, for: Folder)
    refute RecordingStudio.capability_enabled?(:accessible, for: Page)
    assert_includes ApplicationController.ancestors, RecordingStudio::UsesDefaultLayout
  end
end
