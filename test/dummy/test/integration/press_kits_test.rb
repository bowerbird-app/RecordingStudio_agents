# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class PressKitsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "kits-#{SecureRandom.hex(4)}@example.com", password: "Password")
    sign_in @user
    @root = RecordingStudio.root_recording_for(Workspace.create!(name: "Kits #{SecureRandom.hex(4)}"))
    @configuration = RecordingStudioAgents.configuration
    @previous_domain_key = @configuration.chatkit_domain_key
    @previous_provider = @configuration.provider
    @previous_root = @configuration.request_root
    @previous_api_key = RecordingStudioAI.configuration.openai_api_key
    @configuration.chatkit_domain_key = "domain_pk_test"
    @configuration.provider = "openai"
    @configuration.request_root = ->(*) { @root }
    RecordingStudioAI.configuration.openai_api_key = "sk-test"
    Current.actor = @user
    access = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @user)
    assert access.success?, access.error.to_s
  end

  teardown do
    @configuration.chatkit_domain_key = @previous_domain_key
    @configuration.provider = @previous_provider
    @configuration.request_root = @previous_root
    RecordingStudioAI.configuration.openai_api_key = @previous_api_key
  end

  test "the index lists kits and keeps the workspace chat unscoped" do
    hello = record_kit("HELLO HOUSE", "A shophouse in Richmond.")
    record_kit("ACUTE HOUSE", "A wedge in Albert Park.")

    get press_kits_path

    assert_response :success
    assert_select "td a[href='#{press_kit_path(hello)}']", text: "HELLO HOUSE"
    assert_select "td", text: "A shophouse in Richmond."
    assert_select "a[href='#{press_kits_path}']", text: "Press kits"
    assert_includes response.body, "A shophouse in Richmond."
    assert_includes response.body, "Which press kit should we open?"
    assert_includes response.body, "Summarize the press kits in this workspace."
    assert_includes response.body, "Ask about press kits"
    assert_includes response.body, "Compare streets"
    refute_includes response.body, "page_recording_id="
    assert_includes response.body, "lg:grid-cols-4"
    assert_includes response.body, "lg:col-span-1"
    assert_includes response.body, "lg:col-span-3"
    assert_includes response.body, "order-1"
    assert_includes response.body, "lg:order-2"
    assert_includes response.body, "lg:sticky"
    assert_select "td a.flat-pack-link.underline", text: "HELLO HOUSE"
    assert_select "button[aria-label='Open the menu']", text: "Menu"
    assert_select ".lg\\:hidden a[href='#{press_kits_path}']", text: "Press kits"
    assert_select ".lg\\:hidden a[data-turbo-method='delete'][href='#{destroy_user_session_path}']", text: "Sign out"
  end

  test "the show page scopes the chat to that kit" do
    hello = record_kit(
      "HELLO HOUSE",
      "A shophouse in Richmond.",
      content: "RICHMOND\n\n“Most architects would probably run.”\n\nThe Hello wall."
    )
    attach_photo(hello, "The Hello wall")

    get press_kit_path(hello)

    assert_response :success
    assert_includes response.body, "HELLO HOUSE"
    assert_includes response.body, "A shophouse in Richmond."
    assert_includes response.body, "page_recording_id=#{hello.id}"
    assert_includes response.body, "Write a short intro for HELLO HOUSE."
    assert_includes response.body, "Ask about this kit"
    refute_includes response.body, "Ask about HELLO HOUSE"
    assert_includes response.body, "h-[min(40rem,calc(100dvh-16rem))]"
    assert_includes response.body, "The Hello wall"
    assert_includes response.body, "Most architects would probably run."
    assert_select "img[alt='The Hello wall']" do |images|
      src = images.first["src"].to_s
      assert_includes src, "/recording_studio_attachable/attachments/"
      refute_includes src, "active_storage"
    end
    assert_includes response.body, "--carousel-lightbox-image-background-color:var(--surface-muted-background-color)"
    assert_includes response.body, "lg:[&_.flat-pack-carousel\\_\\_viewport]:max-h-[28rem]"
  end

  test "team lines keep their breaks and stay escaped" do
    hello = record_kit("HELLO HOUSE", "A shophouse in Richmond.")
    @root.revise(hello, actor: @user) do |press_kit|
      press_kit.sections = [
        {
          "kind" => "paragraph",
          "text" => "Architect: Ada Lovelace\nEngineer: Grace Hopper\n<script>alert(1)</script>"
        }
      ]
    end

    get press_kit_path(hello)

    assert_response :success
    assert_match(/Architect: Ada Lovelace\s*<br\s*\/?>\s*Engineer: Grace Hopper/, response.body)
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute_includes response.body, "<script>alert"
  end

  test "a kit in this workspace that the actor cannot view is forbidden" do
    shown = record_kit("HELLO HOUSE", "Shown to you.")
    hidden = record_kit("SECRET HOUSE", "Not for you.")
    viewer = User.create!(email: "viewer-#{SecureRandom.hex(4)}@example.com", password: "Password")
    grant = RecordingStudioAccessible.grant_access(
      recording: shown, actor: viewer, role: :view, manager_actor: @user
    )
    assert grant.success?, grant.error.to_s
    sign_in viewer

    get press_kits_path

    assert_response :success
    assert_includes response.body, "HELLO HOUSE"
    refute_includes response.body, "SECRET HOUSE"

    get press_kit_path(hidden)

    assert_response :forbidden
    assert_includes response.body, "You can&#39;t open this press kit"
    refute_includes response.body, "page_recording_id="
  end

  test "a kit outside the current workspace is not shown" do
    other = RecordingStudio.root_recording_for(Workspace.create!(name: "Elsewhere #{SecureRandom.hex(4)}"))
    foreign = other.record(PressKit, actor: @user) do |press_kit|
      press_kit.name = "Other kit"
      press_kit.description = "Not here"
      press_kit.content = "Hidden"
    end

    get press_kit_path(foreign)

    assert_response :not_found
    assert_includes response.body, "That press kit is not in this workspace"
    refute_includes response.body, "page_recording_id="
  end

  private

  def record_kit(name, description, content: "The Hello wall.")
    @root.record(PressKit, actor: @user) do |press_kit|
      press_kit.name = name
      press_kit.description = description
      press_kit.content = content
    end
  end

  def attach_photo(recording, name)
    Current.actor = @user
    access = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @user)
    assert access.success?, access.error.to_s

    path = Rails.root.join("db/press_kit_images/hello-house/01.jpg")
    File.open(path, "rb") do |io|
      result = RecordingStudioAttachable::Services::ImportAttachment.call(
        parent_recording: recording,
        io: io,
        filename: "hello-house-01.jpg",
        content_type: "image/jpeg",
        actor: @user,
        name: name
      )
      assert result.success?, result.error.to_s
    end
  end
end
