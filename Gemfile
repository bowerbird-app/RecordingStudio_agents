# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_agents.gemspec
gemspec

# GitHub-only gems. The gemspec pins the versions; these lines give Bundler a source.
# FlatPack v0.1.356. FloatingFrame shipped in v0.1.354.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.356"
gem "recording_studio", ">= 6.12.0", github: "bowerbird-app/RecordingStudio", tag: "v6.12.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.32.0"
gem "recording_studio_ai", github: "bowerbird-app/RecordingStudio_AI", tag: "v0.21.2"
gem "recording_studio_api", github: "bowerbird-app/RecordingStudio_api", tag: "v0.23.0"
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons", tag: "v0.2.1"
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.7.4"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.8.0"
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v4.1.1"
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.14.0"
gem "view_component", "4.19.0"

gem "devise"
gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
  gem "minitest-mock"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
