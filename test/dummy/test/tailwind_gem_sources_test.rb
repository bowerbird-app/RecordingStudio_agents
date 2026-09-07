# frozen_string_literal: true

require "test_helper"
require "rake"

class TailwindGemSourcesTest < ActiveSupport::TestCase
  setup do
    Dummy::Application.load_tasks
  end

  test "tailwind enhance_sources writes Flatpack, Recording Studio, and Admin scan paths" do
    Rake::Task["tailwindcss:enhance_sources"].reenable
    Rake::Task["tailwindcss:enhance_sources"].invoke

    sources = File.read(Rails.root.join("app/assets/tailwind/gem_sources.css"))
    flatpack = Gem.loaded_specs.fetch("flat_pack").full_gem_path
    studio = Gem.loaded_specs.fetch("recording_studio").full_gem_path
    admin = Gem.loaded_specs.fetch("recording_studio_admin").full_gem_path

    assert_includes sources, "#{flatpack}/app/components/**/*.{rb,erb}"
    assert_includes sources, "#{studio}/app/views/**/*.erb"
    assert_includes sources, "#{admin}/app/views/**/*.erb"
  end

  test "dummy tailwind entry imports generated gem sources" do
    entry = File.read(Rails.root.join("app/assets/tailwind/application.css"))

    assert_includes entry, '@import "./gem_sources.css"'
    assert_includes entry, "RecordingStudio_admin"
    refute_includes entry, "@theme"
    refute_includes entry, ":root {"
    refute_includes entry, "--color-fp-primary"
  end

  test "compiled dummy tailwind includes default layout and admin table utilities" do
    css_path = Rails.root.join("app/assets/builds/tailwind.css")
    css = css_path.exist? ? File.read(css_path) : ""
    unless css.include?("max-w-6xl") && css.include?("inset-y-0")
      Rake::Task["tailwindcss:build"].reenable
      Rake::Task["tailwindcss:build"].invoke
      css = File.read(css_path)
    end

    assert_includes css, "min-h-screen"
    assert_includes css, "max-w-6xl"
    assert_includes css, "inset-y-0"
  end
end
