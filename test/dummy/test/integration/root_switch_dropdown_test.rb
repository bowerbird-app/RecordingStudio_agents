# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class RootSwitchDropdownTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "sign in page uses the users auth screen and is not squished by the default layout" do
    get new_user_session_path

    assert_response :success
    assert_includes response.body, "Welcome back"
    assert_includes response.body, "you@company.com"
    assert_includes response.body, "Continue with email"
    assert_includes response.body, 'data-theme="rounded"'
    refute_includes response.body, "data-recording-studio-default-layout"
    refute_includes response.body, "mt-28"
    refute_includes response.body, "fixed inset-0"
  end

  test "home page renders the root switch dropdown trigger" do
    user = User.find_or_create_by!(email: "root-switch-test@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
      record.skip_confirmation!
    end
    unless user.confirmed?
      user.skip_confirmation!
      user.save!
    end

    sign_in user

    workspace = Workspace.create!(name: "Dropdown Workspace")
    RecordingStudio.create_root_recording!(workspace, actor: user)

    get root_path

    assert_response :success
    assert_includes response.body, workspace.name
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
  end

  test "root switch page renders with the host default layout" do
    user = User.find_or_create_by!(email: "root-switch-page-test@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
      record.skip_confirmation!
    end
    unless user.confirmed?
      user.skip_confirmation!
      user.save!
    end

    sign_in user

    workspace = Workspace.create!(name: "Switch Page Workspace")
    RecordingStudio.create_root_recording!(workspace, actor: user)
    grant_view_on_all_workspaces(user)

    get "/recording_studio_root_switchable/v1/root_switch?scope=all_workspaces"

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    refute_includes response.body, "flat-pack-sidebar-layout"
  end

  test "switching returns to the current page when it is a valid internal route" do
    user = User.find_or_create_by!(email: "root-switch-redirect-test@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
      record.skip_confirmation!
    end
    unless user.confirmed?
      user.skip_confirmation!
      user.save!
    end

    sign_in user

    source_workspace = Workspace.create!(name: "Source Workspace")
    target_workspace = Workspace.create!(name: "Target Workspace")
    target_root_recording = RecordingStudio.create_root_recording!(target_workspace, actor: user)
    RecordingStudio.create_root_recording!(source_workspace, actor: user)
    grant_view_on_all_workspaces(user)

    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: target_root_recording.id,
        return_to: "/docs/install"
      }
    }

    assert_redirected_to "/docs/install"
  end

  test "switching falls back to home when return_to is not a valid internal route" do
    user = User.find_or_create_by!(email: "root-switch-fallback-test@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
      record.skip_confirmation!
    end
    unless user.confirmed?
      user.skip_confirmation!
      user.save!
    end

    sign_in user

    source_workspace = Workspace.create!(name: "Fallback Source Workspace")
    target_workspace = Workspace.create!(name: "Fallback Target Workspace")
    target_root_recording = RecordingStudio.create_root_recording!(target_workspace, actor: user)
    RecordingStudio.create_root_recording!(source_workspace, actor: user)
    grant_view_on_all_workspaces(user)

    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: target_root_recording.id,
        return_to: "/not-a-real-route"
      }
    }

    assert_redirected_to "/"
  end

  private

  # Root Switchable checks `:view` on the resolved current root, which is
  # the first workspace when the device has no saved selection. Seeds load
  # other workspaces ahead of the ones this test creates.
  def grant_view_on_all_workspaces(actor)
    Workspace.find_each do |workspace|
      root = RecordingStudio.root_recording_for(workspace) ||
        RecordingStudio.create_root_recording!(workspace, actor: actor)
      grant_view(actor, root)
    end
  end

  def grant_view(actor, recording)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)

    Current.actor = actor
    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(recording).record(
        RecordingStudio::Access, actor: actor, parent_recording: recording
      ) do |access|
        access.actor = actor
        access.role = "view"
      end
    end
  end
end
