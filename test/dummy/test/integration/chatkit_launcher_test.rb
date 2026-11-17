# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class ChatkitLauncherTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  SANDBOX = RecordingStudioAgents::ChatKitHelper::POPUP_IFRAME_SANDBOX

  setup do
    @user = User.create!(email: "launcher-#{SecureRandom.hex(4)}@example.com", password: "Password") { |user| user.skip_confirmation! }
    sign_in @user
    @configuration = RecordingStudioAgents.configuration
    @previous_launcher = @configuration.launcher
    @previous_icon = @configuration.launcher_icon
    @previous_label = @configuration.launcher_label
    @previous_popup_title = @configuration.instance_variable_get(:@popup_title)
    @previous_actor = @configuration.request_actor
    @previous_root = @configuration.request_root
    @configuration.launcher = true
    workspace = Workspace.create!(name: "Launcher #{SecureRandom.hex(4)}")
    @root = RecordingStudio.create_root_recording!(workspace, actor: @user)
  end

  teardown do
    @configuration.launcher = @previous_launcher
    @configuration.launcher_icon = @previous_icon
    @configuration.launcher_label = @previous_label
    @configuration.instance_variable_set(:@popup_title, @previous_popup_title)
    @configuration.request_actor = @previous_actor
    @configuration.request_root = @previous_root
  end

  test "the layout launcher frames the popup at the bottom left with no padding" do
    get root_path

    assert_response :success
    assert_select ".fp-floating-frame [data-fp-position=?]", "bottom_left"
    assert_select "button[aria-label=?][aria-expanded=?][aria-controls]", "Open chat", "false"
    assert_select "[data-flat-pack--icon-name-value=?]", "chat-bubble-left-ellipsis"
    iframe = css_select("iframe").first
    assert_equal recording_studio_agents.popup_path, iframe["src"]
    assert_equal "Chat", iframe["title"]
    assert_equal SANDBOX, iframe["sandbox"]
    assert_equal "clipboard-write", iframe["allow"]
    assert_equal "fp-floating-frame__mount", css_select(".fp-floating-frame__mount").first["class"]
    frame = css_select("##{RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID}").first
    assert_equal "true", frame["data-turbo-permanent"]
    assert_includes frame["data-controller"], "flat-pack--floating-frame"
    assert_select "script[src*='recording_studio_agents/page_context']", count: 1
    assert_select "script[src*='recording_studio_agents/launcher']", count: 1
    assert_operator response.body.index("recording_studio_agents/page_context"), :<,
      response.body.index("recording_studio_agents/launcher")
    assert_includes SANDBOX, "allow-top-navigation-by-user-activation"
    assert_includes SANDBOX, "allow-scripts"
    assert_includes SANDBOX, "allow-same-origin"
    assert_includes SANDBOX, "allow-forms"
    assert_includes SANDBOX, "allow-popups"
  end

  test "a disabled launcher renders nothing" do
    @configuration.launcher = false

    get root_path

    assert_response :success
    assert_select ".fp-floating-frame", count: 0
    assert_select "iframe", count: 0
  end

  test "the launcher renders nothing when the actor resolver returns nothing" do
    @configuration.request_actor = ->(*) { nil }

    get root_path

    assert_response :success
    assert_select "##{RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID}", count: 0
    assert_select ".fp-floating-frame", count: 0
  end

  test "the launcher renders nothing when the root resolver returns nothing" do
    @configuration.request_root = ->(*) { nil }

    get root_path

    assert_response :success
    assert_select "##{RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID}", count: 0
    assert_select ".fp-floating-frame", count: 0
  end

  test "a launcher lambda that returns false renders nothing" do
    @configuration.launcher = ->(_controller) { false }

    get root_path

    assert_response :success
    assert_select "##{RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID}", count: 0
    assert_select ".fp-floating-frame", count: 0
  end

  test "the launcher lambda stays uncalled when the actor or workspace is missing" do
    @configuration.launcher = ->(*) { raise "launcher lambda ran" }
    @configuration.request_actor = ->(*) { nil }

    get root_path

    assert_response :success
    assert_select "##{RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID}", count: 0

    @configuration.request_actor = @previous_actor
    @configuration.request_root = ->(*) { nil }

    get root_path

    assert_response :success
    assert_select "##{RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID}", count: 0
  end

  test "a launcher lambda that returns true renders the launcher" do
    seen = nil
    @configuration.launcher = lambda do |controller|
      seen = controller.class.name
      true
    end

    get root_path

    assert_response :success
    assert_equal "HomeController", seen
    assert_select "##{RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID}", count: 1
  end

  test "a signed out sign in page has no launcher" do
    sign_out @user

    get new_user_session_path

    assert_response :success
    assert_includes response.body, "Welcome back"
    assert_select "##{RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID}", count: 0
  end

  test "the popup page does not include another launcher" do
    get recording_studio_agents.popup_path

    assert_response :success
    assert_select ".fp-floating-frame", count: 0
  end

  test "the launcher path uses the engine routes when the mount helper is missing" do
    html = with_resolved_person_and_workspace do
      view = HomeController.new.view_context
      view.define_singleton_method(:recording_studio_agents) { raise "mount helper" }
      view.render(inline: "<%= recording_studio_agents_launcher %>")
    end
    path = RecordingStudioAgents::Engine.routes.url_helpers.popup_path

    assert_includes html, %(src="#{path}")
    assert_equal "/recording_studio_agents/popup", path
  end

  test "config sets the icon label and title when the helper leaves them out" do
    @configuration.launcher_icon = :sparkles
    @configuration.launcher_label = "Ask the studio"
    @configuration.popup_title = "Studio chat"

    get root_path

    assert_response :success
    assert_select "button[aria-label=?]", "Ask the studio"
    assert_select "[data-flat-pack--icon-name-value=?]", "sparkles"
    assert_equal "Studio chat", css_select("iframe").first["title"]
    assert_select "h2", text: "Studio chat"
  end

  test "label title and position overrides reach the frame" do
    html = with_resolved_person_and_workspace do
      HomeController.renderer.render(
        inline: <<~ERB
          <%= recording_studio_agents_launcher(label: "Ask", title: "Studio chat", position: :top_right) %>
        ERB
      )
    end

    assert_includes html, "Ask"
    assert_includes html, "Studio chat"
    assert_includes html, 'data-flat-pack--icon-name-value="chat-bubble-left-ellipsis"'
    assert_includes html, 'data-fp-position="top_right"'
    assert_includes html, %(src="#{RecordingStudioAgents::Engine.routes.url_helpers.popup_path}")
    assert_includes html, %(sandbox="#{SANDBOX}")
    assert_includes html, 'class="fp-floating-frame__mount"'
  end

  test "two renders share one launcher id so Turbo can keep the node" do
    renderer = HomeController.renderer
    first, second = with_resolved_person_and_workspace do
      [
        renderer.render(inline: "<%= recording_studio_agents_launcher %>"),
        renderer.render(inline: "<%= recording_studio_agents_launcher %>")
      ]
    end
    id = RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID

    assert_includes first, %(id="#{id}")
    assert_includes second, %(id="#{id}")
    assert_includes first, 'data-turbo-permanent="true"'
    refute_match(/fp-floating-frame-[0-9a-f]{8}/, first)
  end

  private

  # Renderer and a bare controller have no session, so the host resolvers
  # would hide the launcher. These examples only check the frame markup.
  def with_resolved_person_and_workspace
    @configuration.request_actor = ->(*) { @user }
    @configuration.request_root = ->(*) { @root }
    yield
  ensure
    @configuration.request_actor = @previous_actor
    @configuration.request_root = @previous_root
  end
end
