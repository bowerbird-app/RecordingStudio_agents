# frozen_string_literal: true

require "test_helper"

class RecordingStudioAgentsTest < Minitest::Test
  def test_version_matches_release
    assert_equal "0.21.0", ::RecordingStudioAgents::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudioAgents::Engine
  end

  def test_gemspec_pins_recording_studio_and_ai
    gemspec = File.read(File.expand_path("../recording_studio_agents.gemspec", __dir__))

    assert_includes gemspec, 'spec.add_dependency "flat_pack", ">= 0.1.354"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio", "~> 7.7"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_ai", "~> 0.25"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_api", ">= 0.26.0", "< 2.0"'
    assert_includes gemspec, 'spec.add_dependency "view_component", ">= 4.14", "< 5"'
    assert_includes gemspec, "https://github.com/bowerbird-app/RecordingStudio_agents"
    refute_includes gemspec, "recording_studio_mcp"
  end

  def test_root_gemfile_pins_recording_studio_seven
    gemfile = File.read(File.expand_path("../Gemfile", __dir__))

    assert_full_pin gemfile, "recording_studio", "~> 7.8", "RecordingStudio", "v7.8.0"
    assert_full_pin gemfile, "recording_studio_ai", "~> 0.26", "RecordingStudio_AI", "v0.26.0"
    refute_includes gemfile, 'tag: "v7.0.0"'
    refute_includes gemfile, 'tag: "v0.24.0"'
    assert_full_pin gemfile, "recording_studio_api", "~> 1.21", "RecordingStudio_api", "v1.21.2"
    refute_includes gemfile, "79723ed015318b790069b7c6cccae7d11d52dcf1"
    refute_includes gemfile, "until 0.20.0 is tagged"
    assert_full_pin gemfile, "recording_studio_logs", "~> 0.9", "RecordingStudio_logs", "v0.9.0"
    assert_full_pin gemfile, "recording_studio_metrics", "~> 0.10", "RecordingStudio_metrics", "v0.10.0"
    assert_full_pin gemfile, "flat_pack", "~> 0.2", "flatpack", "v0.2.0"
    assert_full_pin gemfile, "recording_studio_accessible", "~> 0.58", "RecordingStudio_accessible", "v0.58.0"
    assert_full_pin gemfile, "recording_studio_icons", "~> 0.5", "RecordingStudio_icons", "v0.5.0"
    assert_full_pin gemfile, "recording_studio_moveable", "~> 6.1", "RecordingStudio_moveable", "v6.1.0"
    assert_full_pin gemfile, "recording_studio_trashable", "~> 1.3", "RecordingStudio_trashable", "v1.3.0"
    refute_includes gemfile, "1fcbafe94f8eb118f0a22182f63f5110fcc97a56"
    refute_includes gemfile, "widen_recording_studio_requirement"
    refute_includes gemfile, 'branch: "main"'
    assert_includes gemfile, 'gem "view_component", "~> 4.19"'
    assert_includes gemfile, 'gem "puma", "~> 8.1"'
    refute_includes gemfile, 'tag: "v4.7.0"'
    refute_includes gemfile, 'tag: "v0.1.254"'
    refute_includes gemfile, 'github: "bowerbird-app/RecordingStudio", tag: "v6.1.0"'
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

  def test_dummy_gemfile_pins_verified_4x_github_tags
    gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    assert_full_pin gemfile, "recording_studio", "~> 7.8", "RecordingStudio", "v7.8.0"
    refute_includes gemfile, 'tag: "v7.3.0"'
    assert_full_pin gemfile, "flat_pack", "~> 0.2", "flatpack", "v0.2.0"
    assert_includes gemfile, 'gem "view_component", "~> 4.19"'
    assert_includes gemfile, 'gem "puma", "~> 8.1"'
    refute_includes gemfile, "widen_recording_studio_requirement"
    refute_includes gemfile, 'branch: "main"'
    refute_includes gemfile, 'tag: "v4.7.0"'
    refute_includes gemfile, 'tag: "v0.1.254"'
    assert_full_pin gemfile, "recording_studio_ai", "~> 0.26", "RecordingStudio_AI", "v0.26.0"
    refute_includes gemfile, 'tag: "v0.24.0"'
    refute_includes gemfile, "79723ed015318b790069b7c6cccae7d11d52dcf1"
    refute_includes gemfile, "until 0.20.0 is tagged"
    assert_full_pin gemfile, "recording_studio_metrics", "~> 0.10", "RecordingStudio_metrics", "v0.10.0"
    refute_includes gemfile, 'tag: "v4.5.0"'
    assert_full_pin gemfile, "recording_studio_accessible", "~> 0.58", "RecordingStudio_accessible", "v0.58.0"
    assert_full_pin gemfile, "recording_studio_trashable", "~> 1.3", "RecordingStudio_trashable", "v1.3.0",
                    "require: false"
    refute_includes gemfile, 'tag: "v4.6.0"'
    refute_includes gemfile, 'tag: "v0.10.0", require: false'
    assert_full_pin gemfile, "recording_studio_root_switchable", "~> 0.17", "RecordingStudio_root_switchable",
                    "v0.17.0"
    assert_full_pin gemfile, "recording_studio_cache", "~> 0.8", "RecordingStudio_cache", "v0.8.0"
    refute_includes gemfile, 'github: "bowerbird-app/RecordingStudio_cache", tag: "v0.5.0"'
    refute_includes gemfile, 'github: "bowerbird-app/RecordingStudio_site_settings", tag: "v0.5.6"'
    assert_full_pin gemfile, "recording_studio_logs", "~> 0.9", "RecordingStudio_logs", "v0.9.0"
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_Oauth", tag: "v0.25.1"'
    mcp_pin = [
      'gem "recording_studio_mcp", "~> 0.45.2",',
      'github: "bowerbird-app/RecordingStudio_MCP", tag: "v0.45.2"'
    ].join(" ")
    assert_includes gemfile, mcp_pin
    assert_full_pin gemfile, "recording_studio_moveable", "~> 6.1", "RecordingStudio_moveable", "v6.1.0"
    assert_full_pin gemfile, "recording_studio_icons", "~> 0.5", "RecordingStudio_icons", "v0.5.0"
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_users", tag: "v0.37.0"'
    assert_full_pin gemfile, "recording_studio_attachable", "~> 0.34", "RecordingStudio_attachable", "v0.34.0",
                    "require: false"
    assert_full_pin gemfile, "recording_studio_api", "~> 1.21", "RecordingStudio_api", "v1.21.3"
    assert_full_pin gemfile, "recording_studio_admin", "~> 2.20", "RecordingStudio_admin", "v2.20.0"
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_site_settings", tag: "v0.6.0"'
    refute_includes gemfile, 'github: "bowerbird-app/RecordingStudio", tag: "v6.1.0"'
    importmap = File.read(File.expand_path("dummy/config/importmap.rb", __dir__))
    install_page = File.read(File.expand_path("dummy/install_page.html", __dir__))
    refute_includes importmap, "flat_pack/heroicons"
    refute_includes importmap, "icon_controller"
    refute_includes install_page, "flat_pack/heroicons"
    refute_includes install_page, "icon_controller"
    refute_includes gemfile, "recording_studio/v3.0.0"
    refute_includes gemfile, 'tag: "v4.4.0"'
    refute_includes gemfile, 'tag: "v4.3.0"'
    refute_includes gemfile, 'tag: "v4.2.2"'
    refute_includes gemfile, 'tag: "v4.2.1"'
    refute_includes gemfile, 'tag: "v4.2.0"'
    refute_includes gemfile, 'tag: "v0.9.1"'
    refute_includes gemfile, 'github: "bowerbird-app/RecordingStudio_cache", tag: "v0.6.3"'
    refute_includes gemfile, 'tag: "v0.1.177"'
    refute_includes gemfile, 'tag: "v0.1.133"'
    refute_includes gemfile, 'tag: "0.3.1"'
  end

  def test_dummy_schema_includes_accessible_depends_on_recording_id
    schema = File.read(File.expand_path("dummy/db/schema.rb", __dir__))
    migration = File.read(
      File.expand_path(
        "dummy/db/migrate/20260911024811_add_depends_on_recording_id_to_recording_studio_accesses.rb",
        __dir__
      )
    )

    assert_includes schema, 't.uuid "depends_on_recording_id"'
    assert_includes schema, "index_recording_studio_accesses_on_depends_on_recording_id"
    assert_includes migration, "add_column :recording_studio_accesses, :depends_on_recording_id, :uuid"
    assert_includes schema, 'create_table "recording_studio_access_invitations"'
    assert_includes schema, "idx_rs_access_invitations_token_digest"
    invitation_migration = File.read(
      File.expand_path(
        "dummy/db/migrate/20261001000011_create_recording_studio_access_invitations.rb",
        __dir__
      )
    )
    assert_includes invitation_migration, "create_table :recording_studio_access_invitations"
    assert_includes schema, 't.string "role", default: "view", null: false'
    refute_includes schema, 't.integer "role", default: 0, null: false'
    role_migration = Dir.glob(
      File.expand_path("dummy/db/migrate/*_change_recording_studio_accesses_role_to_string.rb", __dir__)
    ).max
    assert role_migration, "expected role-column migration in dummy db/migrate"
    assert_includes File.read(role_migration), "change_column :recording_studio_accesses, :role, :string"

    assert_includes schema, 'create_table "recording_studio_access_constraints"'
    assert_includes schema, 'create_table "recording_studio_access_rules"'
    assert_includes schema, "index_recording_studio_access_constraints_on_action"
    assert_includes schema, "index_recording_studio_access_rules_on_action"
    constraint_migration = Dir.glob(
      File.expand_path("dummy/db/migrate/*_create_recording_studio_access_constraints.rb", __dir__)
    ).max
    rule_migration = Dir.glob(
      File.expand_path("dummy/db/migrate/*_create_recording_studio_access_rules.rb", __dir__)
    ).max
    assert constraint_migration, "expected access constraints migration in dummy db/migrate"
    assert rule_migration, "expected access rules migration in dummy db/migrate"
    assert_includes File.read(constraint_migration), "create_table :recording_studio_access_constraints"
    assert_includes File.read(rule_migration), "create_table :recording_studio_access_rules"
  end

  def test_template_does_not_ship_copied_core_hooks_or_base_service
    refute File.exist?(File.expand_path("../lib/recording_studio_agents/hooks.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_agents/services/base_service.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_agents/services/example_service.rb", __dir__))
  end

  def test_template_example_capability_and_extension_installer_are_gone
    root = File.expand_path("..", __dir__)

    refute File.exist?(File.join(root, "lib/recording_studio_agents/capabilities/example.rb"))
    refute File.exist?(File.join(root, "lib/recording_studio_agents/extension_installer.rb"))
    refute File.exist?(File.join(root, "app/controllers/recording_studio_agents/home_controller.rb"))
    refute RecordingStudio.registered_capabilities.key?(:example)
  end

  def test_dummy_app_uses_recording_studio_default_layout
    application_controller_path = File.expand_path("dummy/app/controllers/application_controller.rb", __dir__)
    controller_source = File.read(application_controller_path)

    assert_includes controller_source, "recording_studio_layout { RecordingStudioAgents.configuration.layout }"
    assert_includes controller_source, 'return "application" if devise_controller?'
    refute_includes controller_source, "UsesDefaultLayout"
    refute_includes controller_source, "recording_studio/default_layout"
    refute_includes controller_source, "flat_pack_sidebar"
    refute File.exist?(File.expand_path("dummy/app/views/layouts/flat_pack_sidebar.html.erb", __dir__))
    refute File.exist?(File.expand_path("dummy/app/views/layouts/flat_pack/_sidebar.html.erb", __dir__))
  end

  def test_dummy_login_layout_keeps_flatpack_assets_without_tight_main_offset
    application_layout = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))

    assert_includes application_layout, '<html data-theme="rounded">'
    assert_includes application_layout, 'stylesheet_link_tag "flat_pack/variables"'
    assert_includes application_layout, 'stylesheet_link_tag "flat_pack/application"'
    assert_includes application_layout, 'stylesheet_link_tag "flat_pack/rich_text"'
    assert_includes application_layout, "javascript_importmap_tags"
    assert_includes application_layout, "min-h-screen"
    refute_includes application_layout, "mt-28"
    refute_includes application_layout, "flat_pack_sidebar"
    variables_at = application_layout.index('stylesheet_link_tag "flat_pack/variables"')
    tailwind_at = application_layout.index('stylesheet_link_tag "tailwind"')
    assert_operator variables_at, :<, tailwind_at
  end

  def test_popup_layout_uses_the_configured_stylesheet
    layout = File.read(File.expand_path("../app/views/layouts/recording_studio_agents/popup.html.erb", __dir__))

    assert_includes layout, "configuration.popup_stylesheet"
    assert_includes layout, "configuration.popup_theme"
    refute_includes layout, 'data-theme="rounded"'
    launcher = File.read(File.expand_path("../app/assets/javascripts/recording_studio_agents/launcher.js", __dir__))
    assert_includes launcher, "recording_studio_agents_launcher"
    assert_includes launcher, "turbo:load"
    refute_includes layout, 'stylesheet_link_tag "tailwind"'
  end

  def test_dummy_tailwind_keeps_flatpack_theme_selection_in_flatpack
    tailwind_source = File.read(File.expand_path("dummy/app/assets/tailwind/application.css", __dir__))

    assert_includes tailwind_source, "../../../vendor/engines/flat_pack/app/components"
    assert_includes tailwind_source, "../../../vendor/engines/recording_studio/app/views"
    refute_includes tailwind_source, "vendor/bundle/**/flatpack/app/components"
    refute_includes tailwind_source, "recordingstudio-*"
    refute_includes tailwind_source, "@theme"
    refute_includes tailwind_source, ":root {"
    refute_includes tailwind_source, "--color-fp-primary"

    refute File.exist?(
      File.expand_path("dummy/app/views/recording_studio/_default_layout_head.html.erb", __dir__)
    )

    rake_task = File.read(File.expand_path("dummy/lib/tasks/tailwindcss.rake", __dir__))
    assert_includes rake_task, "FlatPack::Engine.root"
    assert_includes rake_task, "RecordingStudio::Engine.root"
    assert_includes rake_task, "tailwindcss:link_engine_sources"
  end

  def test_recording_studio_keeps_strict_recordable_declarations_enabled
    initializer_path = File.expand_path("dummy/config/initializers/recording_studio.rb", __dir__)
    initializer_source = File.read(initializer_path)

    assert_includes initializer_source, "config.require_recordable_declarations = true"
    assert_includes initializer_source, "config.authorize_write"
    assert_includes initializer_source, '"RecordingStudioAgents::Session"'
    assert_includes initializer_source, '"RecordingStudioUser::People"'
    assert_includes initializer_source, '"RecordingStudioUser::Profile"'
    assert_includes initializer_source, '"RecordingStudioAttachable::Attachment"'
    refute_includes initializer_source, '"RecordingStudioAttachable::Library"'
    refute_includes initializer_source, '"RecordingStudioAttachable::Placement"'
    assert_includes initializer_source, '"RecordingStudioSiteSettings::SiteSetting"'
    assert_includes initializer_source, '"RecordingStudio::Access"'
    assert_includes initializer_source, '"RecordingStudioApi::AdminApi"'
    assert_includes initializer_source, '"RecordingStudioApi::ApiClient"'
    refute_includes initializer_source, "config.include_children"
    refute_includes initializer_source, "config.features."
    refute_includes initializer_source, "v3"
  end

  def test_dummy_readme_explains_dummy_app_purpose
    readme_path = File.expand_path("dummy/README.md", __dir__)
    readme_source = File.read(readme_path)

    assert_includes readme_source, "This Rails app exists to validate the Recording Studio addon template"
    assert_includes readme_source, "/recording_studio"
    assert_includes readme_source, "redirects to `/`"
    refute_includes readme_source, "flat_pack_sidebar"
  end

  def test_product_readme_is_the_template_guide
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "RecordingStudio"
    assert_includes readme, "Recording Studio gemspec `~> 7.7`"
    assert_full_pin readme, "recording_studio", "~> 7.8", "RecordingStudio", "v7.8.0"
    assert_full_pin readme, "flat_pack", "~> 0.2", "flatpack", "v0.2.0"
    refute_includes readme, "1fcbafe94f8eb118f0a22182f63f5110fcc97a56"
    refute_includes readme, "dummy GitHub tag `v4.7.0`"
    assert_full_pin readme, "recording_studio_ai", "~> 0.26", "RecordingStudio_AI", "v0.26.0"
    assert_includes readme, "Accessible dummy GitHub tag `v0.58.0`"
    refute_includes readme, "79723ed015318b790069b7c6cccae7d11d52dcf1"
    refute_includes readme, "until 0.20.0 is tagged"
    assert_includes readme, "Metrics dummy GitHub tag `v0.10.0`"
    refute_includes readme, "dummy GitHub tag `v4.5.0`"
    refute_includes readme, "dummy GitHub tag `v0.1.254`"
    assert_includes readme, "Oauth dummy GitHub tag `v0.25.1`"
    assert_includes readme, "dummy GitHub tag `v0.45.2`"
    assert_includes readme, "Recording Studio API dummy GitHub tag `v1.21.3`"
    assert_includes readme, "RecordingStudioApi::RateLimit.check"
    assert_includes readme, "fail_closed: true"
    refute_includes readme, "increment script"
    assert_includes readme, "`pending`, `ok`, `error`, `refused`, `limited`, or `unknown`"
    assert_includes readme, "Moveable dummy GitHub tag `v6.1.0`"
    assert_includes readme, "Icons dummy GitHub tag `v0.5.0`"
    assert_includes readme, "root GitHub tag `v0.2.0`"
    assert_includes readme, "dummy GitHub tag `v0.2.0`"
    assert_includes readme, "Logs dummy GitHub tag `v0.9.0`"
    assert_includes readme, "Users dummy GitHub tag `v0.37.0`"
    assert_includes readme, "Trashable dummy GitHub tag `v1.3.0`"
    assert_includes readme, "Attachable dummy GitHub tag `v0.34.0`"
    assert_includes readme, "Cache dummy GitHub tag `v0.8.0`"
    assert_includes readme, "Site Settings dummy GitHub tag `v0.6.0`"
    assert_includes readme, "Admin dummy GitHub tag `v2.20.0`"
    refute_includes readme, "Cache dummy GitHub tag `v0.5.0`"
    assert_includes readme, "Root Switchable dummy GitHub tag `v0.17.0`"
    refute_includes readme, "widen_recording_studio_requirement"
    refute_includes readme, "Site Settings dummy GitHub tag `v0.5.6`"
    refute_includes readme, "dummy GitHub tag `v4.4.0`"
    refute_includes readme, "dummy GitHub tag `v4.3.0`"
    refute_includes readme, "dummy GitHub tag `v4.2.2`"
    refute_includes readme, "dummy GitHub tag `v4.2.1`"
    refute_includes readme, "dummy GitHub tag `v4.2.0`"
    refute_includes readme, "v0.1.177"
    refute_includes readme, "v0.9.1"
    refute_includes readme, "v0.1.133"
    refute_includes readme, "v3 declarations"
    refute_includes readme, "RecordingStudio v3"
    refute_includes readme, "ExampleService"
    refute_includes readme, "recording_studio/v3.0.0"
  end

  def test_dummy_home_page_uses_demo_title_only
    view_path = File.expand_path("dummy/app/views/home/index.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, 'title: "Template Demo"'
    assert_includes view_source, 'subtitle: "This dummy app is the browser-facing demo surface for the template."'
    assert_includes view_source, "FlatPack::Card::Component"
    assert_includes view_source, "dummy_page_nav"
    refute_includes view_source, "variant: :h1"
    refute_includes view_source, 'title: "Demo"'
    refute_includes view_source, "FlatPack::Breadcrumb::Component"
  end

  def test_dummy_docs_pages_use_minimal_flatpack_documentation_components
    docs_view_paths = Dir[File.expand_path("dummy/app/views/docs/*.html.erb", __dir__)].reject do |view_path|
      File.basename(view_path).start_with?("_")
    end
    refute_empty docs_view_paths

    docs_view_paths.each do |view_path|
      view_source = File.read(view_path)

      assert_includes view_source, "dummy_page_nav"
      refute_includes view_source, "FlatPack::PageTitle::Component"
      refute_includes view_source, "FlatPack::Card::Component"
      refute_includes view_source, "FlatPack::Breadcrumb::Component"
    end

    methods_view = File.read(File.expand_path("dummy/app/views/docs/methods.html.erb", __dir__))
    assert_includes methods_view, "FlatPack::SectionTitle::Component"
    assert_includes methods_view, "FlatPack::CodeBlock::Component"

    gem_views_view = File.read(File.expand_path("dummy/app/views/docs/gem_views.html.erb", __dir__))
    assert_includes gem_views_view, "FlatPack::Table::Component"
    refute_includes gem_views_view, "FlatPack::List::Component"

    recordable_types_view = File.read(File.expand_path("dummy/app/views/docs/recordable_types.html.erb", __dir__))
    assert_includes recordable_types_view, "FlatPack::List::Component"
    refute_includes recordable_types_view, "v3 parent/root"

    recordings_tree_view = File.read(File.expand_path("dummy/app/views/docs/recordings_tree.html.erb", __dir__))
    assert_includes recordings_tree_view, "FlatPack::Tree::Component"
    refute_includes recordings_tree_view, "Current structure"
    refute_includes recordings_tree_view, "This tree is generated from RecordingStudio::Recording records"
  end

  def test_dummy_recordings_tree_view_omits_structure_section_copy
    recordings_tree_view = File.read(File.expand_path("dummy/app/views/docs/recordings_tree.html.erb", __dir__))

    assert_includes recordings_tree_view, 'title: "Recordings tree"'
    assert_includes recordings_tree_view, "FlatPack::Tree::Component"
    recording_tree_partial = File.read(File.expand_path("dummy/app/views/docs/_recording_tree_node.html.erb", __dir__))
    assert_includes recording_tree_partial, "parent_builder.node"
    refute_includes recordings_tree_view, "Current structure"
    refute_includes recordings_tree_view, "This tree is generated from RecordingStudio::Recording records"
  end

  def assert_full_pin(source, name, requirement, repo, tag, trailer = nil) # rubocop:disable Metrics/ParameterLists
    line = %(gem "#{name}", "#{requirement}", github: "bowerbird-app/#{repo}", tag: "#{tag}")
    line = "#{line}, #{trailer}" if trailer
    assert_includes source, line
  end

  def test_engine_does_not_ship_a_home_view
    view_path = File.expand_path("../app/views/recording_studio_agents/home/index.html.erb", __dir__)

    refute File.exist?(view_path)
  end
end
