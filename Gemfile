# frozen_string_literal: true

source "https://rubygems.org"

require_relative "config/bundler_recording_studio_5"

# Specify your gem's dependencies in recording_studio_agents.gemspec
gemspec

# GitHub-only gems. The gemspec pins the versions; these lines give Bundler a source.
# Flatpack 0.1.275 is the lowest tag Recording Studio 5.0.0 accepts.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.275"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v5.0.0"
gem "recording_studio_ai", github: "bowerbird-app/RecordingStudio_AI", tag: "v0.15.1"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.3.1"

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
