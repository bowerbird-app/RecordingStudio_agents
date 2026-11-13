# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class ChatkitLauncherTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  SANDBOX = RecordingStudioAgents::ChatKitHelper::POPUP_IFRAME_SANDBOX

  setup do
    @user = User.create!(email: "launcher-#{SecureRandom.hex(4)}@example.com", password: "Password")
    sign_in @user
    @configuration = RecordingStudioAgents.configuration
    @previous_launcher = @configuration.launcher
    @configuration.launcher = true
  end

  teardown do
    @configuration.launcher = @previous_launcher
  end

  test "the layout launcher frames the popup at the bottom left with no padding" do
    get root_path

    assert_response :success
    assert_select ".fp-floating-frame [data-fp-position=?]", "bottom_left"
    assert_select "button[aria-label=?][aria-expanded=?][aria-controls]", "Open chat", "false"
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

  test "the popup page does not include another launcher" do
    get recording_studio_agents.popup_path

    assert_response :success
    assert_select ".fp-floating-frame", count: 0
  end

  test "the launcher path uses the engine routes when the mount helper is missing" do
    view = HomeController.new.view_context
    view.define_singleton_method(:recording_studio_agents) { raise "mount helper" }

    html = view.render(inline: "<%= recording_studio_agents_launcher %>")
    path = RecordingStudioAgents::Engine.routes.url_helpers.popup_path

    assert_includes html, %(src="#{path}")
    assert_equal "/recording_studio_agents/popup", path
  end

  test "label title and position overrides reach the frame" do
    html = HomeController.renderer.render(
      inline: <<~ERB
        <%= recording_studio_agents_launcher(label: "Ask", title: "Studio chat", position: :top_right) %>
      ERB
    )

    assert_includes html, "Ask"
    assert_includes html, "Studio chat"
    assert_includes html, 'data-fp-position="top_right"'
    assert_includes html, %(src="#{RecordingStudioAgents::Engine.routes.url_helpers.popup_path}")
    assert_includes html, %(sandbox="#{SANDBOX}")
    assert_includes html, 'class="fp-floating-frame__mount"'
  end

  test "two renders share one launcher id so Turbo can keep the node" do
    renderer = HomeController.renderer
    first = renderer.render(inline: "<%= recording_studio_agents_launcher %>")
    second = renderer.render(inline: "<%= recording_studio_agents_launcher %>")
    id = RecordingStudioAgents::ChatKitHelper::LAUNCHER_ELEMENT_ID

    assert_includes first, %(id="#{id}")
    assert_includes second, %(id="#{id}")
    assert_includes first, 'data-turbo-permanent="true"'
    refute_match(/fp-floating-frame-[0-9a-f]{8}/, first)
  end
end
