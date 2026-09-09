# frozen_string_literal: true

require "test_helper"

class RecordingStudioAgentsTest < Minitest::Test
  def test_version_matches_release
    assert_equal "0.4.6", ::RecordingStudioAgents::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudioAgents::Engine
  end

  def test_gemspec_pins_locked_dependencies
    gemspec = File.read(File.expand_path("../recording_studio_agents.gemspec", __dir__))

    assert_includes gemspec, 'spec.add_dependency "recording_studio", "~> 4.2"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_ai", "~> 0.3"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_admin", "~> 2.0"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_accessible", "~> 0.6"'
    assert_includes gemspec, 'spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_agents"'
  end

  def test_gemspec_excludes_cursor_config
    spec = Gem::Specification.load(File.expand_path("../recording_studio_agents.gemspec", __dir__))
    cursor_files = spec.files.select { |path| path == ".cursor" || path.split("/").include?(".cursor") }

    assert_empty cursor_files, "gemspec must not package .cursor/ (got #{cursor_files.inspect})"
  end

  def test_cursor_environment_is_repo_managed_without_snapshot
    path = File.expand_path("../.cursor/environment.json", __dir__)
    json = JSON.parse(File.read(path))

    assert_equal "recording-studio-agents", json["name"]
    assert_equal ".cursor/install.sh", json["install"]
    assert_equal ".cursor/start.sh", json["start"]
    refute json.key?("snapshot"), "snapshot pins a Personal build and skips install"
    refute json.key?("agentCanUpdateSnapshot")
  end

  def test_cursor_install_still_fetches_skills
    install_script = File.read(File.expand_path("../.cursor/install.sh", __dir__))

    assert_includes install_script, "fetch-skills.sh"
  end

  def test_dummy_gemfile_pins_verified_github_tags
    gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio", tag: "v4.2.0"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.7.0"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_admin", tag: "v2.0.2"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_AI", tag: "v0.3.1"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_root_switchable", tag: "v0.5.0"'
    assert_includes gemfile, 'github: "bowerbird-app/flatpack", tag: "v0.1.143"'
  end

  def test_template_does_not_ship_copied_core_hooks_or_example_capability
    refute File.exist?(File.expand_path("../lib/recording_studio_agents/hooks.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_agents/capabilities/example.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_agents/services/base_service.rb", __dir__))
  end

  def test_dummy_importmap_pins_admin_screen_controllers
    importmap = File.read(File.expand_path("dummy/config/importmap.rb", __dir__))
    application_js = File.read(File.expand_path("dummy/app/javascript/application.js", __dir__))

    assert_includes importmap, 'pin "@hotwired/turbo-rails", to: "turbo.min.js"'
    assert_includes importmap, "RecordingStudioAdmin::Engine.root.join(\"app/javascript/recording_studio_admin/controllers\")"
    assert_includes importmap, 'under: "controllers/recording_studio_admin"'
    assert_includes application_js, 'import "@hotwired/turbo-rails"'
  end

  def test_dummy_app_uses_recording_studio_default_layout
    application_controller_path = File.expand_path("dummy/app/controllers/application_controller.rb", __dir__)
    controller_source = File.read(application_controller_path)

    assert_includes controller_source, "include RecordingStudio::UsesDefaultLayout"
    assert_includes controller_source, '"recording_studio/default_layout"'
    assert_includes controller_source, "devise_controller? ? \"application\""
    refute_includes controller_source, "flat_pack_sidebar"
    refute File.exist?(File.expand_path("dummy/app/views/layouts/flat_pack_sidebar.html.erb", __dir__))
  end

  def test_dummy_login_layout_keeps_flatpack_assets_without_tight_main_offset
    application_layout = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))

    assert_includes application_layout, '<html data-theme="rounded">'
    assert_includes application_layout, 'stylesheet_link_tag "flat_pack/variables"'
    assert_includes application_layout, "javascript_importmap_tags"
    assert_includes application_layout, "min-h-screen"
    refute_includes application_layout, "mt-28"
    refute_includes application_layout, "flat_pack_sidebar"
  end

  def test_dummy_tailwind_keeps_flatpack_theme_selection_in_flatpack
    tailwind_source = File.read(File.expand_path("dummy/app/assets/tailwind/application.css", __dir__))
    rake = File.read(File.expand_path("dummy/lib/tasks/tailwind_gem_sources.rake", __dir__))

    assert_includes tailwind_source, '@import "./gem_sources.css"'
    assert_includes tailwind_source, "../../../vendor/bundle/**/flatpack/app/components/**/*.{rb,erb}"
    assert_includes tailwind_source, "flatpack-*/app/components/**/*.{rb,erb}"
    assert_includes tailwind_source, "RecordingStudio*/app/views/**/*.erb"
    assert_includes tailwind_source, "RecordingStudio_admin"
    assert_includes rake, "task enhance_sources"
    refute_includes tailwind_source, "@theme"
    refute_includes tailwind_source, ":root {"
    refute_includes tailwind_source, "--color-fp-primary"
  end

  def test_recording_studio_keeps_strict_declarations_and_admin_root
    initializer_path = File.expand_path("dummy/config/initializers/recording_studio.rb", __dir__)
    initializer_source = File.read(initializer_path)

    assert_includes initializer_source, "config.require_recordable_declarations = true"
    assert_includes initializer_source, '"AdminRoot"'
    assert_includes initializer_source, '"Workspace"'
    refute_includes initializer_source, "config.include_children"
    refute_includes initializer_source, "v3"
  end

  def test_dummy_readme_explains_agents_host
    readme_path = File.expand_path("dummy/README.md", __dir__)
    readme_source = File.read(readme_path)

    assert_includes readme_source, "page librarian"
    assert_includes readme_source, "workspace root"
    assert_includes readme_source, "Getting Started page as context"
    assert_includes readme_source, "/admin"
    assert_includes readme_source, "Last 4 weeks"
    assert_includes readme_source, "Usage by agent"
    assert_includes readme_source, "/recording_studio"
    refute_includes readme_source, "flat_pack_sidebar"
    refute_includes readme_source, "/docs/install"
  end

  def test_product_readme_explains_agents
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "Recording Studio Agents"
    assert_includes readme, "Agent#run"
    assert_includes readme, "HandoffRequested"
    assert_includes readme, "job_id"
    refute_includes readme, "job_id:\#{executions}"
    assert_includes readme, "optional_skills"
    assert_includes readme, "pack:"
    assert_includes readme, "Progress.for"
    assert_includes readme, "Last 4 weeks"
    assert_includes readme, "Usage by agent"
    assert_includes readme, "source_recording"
    assert_includes readme, "context_recording"
    assert_includes readme, "Each entry must cite a source recording"
    refute_includes readme, "ExampleService"
    refute_includes readme, "recordable"
    refute_includes readme, "\u2014"
  end

  def test_dummy_home_page_is_the_page_librarian_demo
    view_path = File.expand_path("dummy/app/views/home/index.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, 'title: "Page librarian"'
    assert_includes view_source, "Find Getting Started"
    assert_includes view_source, "dummy_page_nav"
    assert_includes view_source, "FlatPack::List::Component"
    assert_includes view_source, "progress_heading"
    controller_source = File.read(File.expand_path("dummy/app/controllers/home_controller.rb", __dir__))
    assert_includes controller_source, "What it did"
    assert_includes controller_source, "On it"
    refute_includes view_source, "FlatPack::Card::Component"
    refute_includes view_source, "Template Demo"
  end

  def test_dummy_does_not_ship_template_docs_pages
    refute File.exist?(File.expand_path("dummy/app/controllers/docs_controller.rb", __dir__))
    refute File.exist?(File.expand_path("dummy/app/views/docs/install.html.erb", __dir__))
  end

  def test_dummy_uses_accessible_roots_and_a_request_scoped_generate_hook
    switchable = File.read(File.expand_path("dummy/config/initializers/recording_studio_root_switchable.rb", __dir__))
    controller = File.read(File.expand_path("dummy/app/controllers/agents_controller.rb", __dir__))
    stub = File.read(File.expand_path("dummy/config/initializers/dummy_generate_stub.rb", __dir__))

    assert_includes switchable, "root_recordings_for"
    refute_includes switchable, "access_check = ->(**) { true }"
    assert_includes controller, "DummyGenerateStub.with_hook"
    refute_includes controller, "define_method(:generate)"
    assert_includes stub, "Thread.current"
    assert_includes File.read(File.expand_path("dummy/test/support_clerk_agent_test.rb", __dir__)),
                    "DummyGenerateStub.with_hook"
  end

  def test_engine_does_not_ship_a_home_view
    view_path = File.expand_path("../app/views/recording_studio_agents/home/index.html.erb", __dir__)

    refute File.exist?(view_path)
  end
end
