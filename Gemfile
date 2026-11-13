# frozen_string_literal: true

source "https://rubygems.org"

# Accessible, Trashable, and Icons still reject recording_studio 6.1.0.
# See test/support/widen_recording_studio_requirement.rb.
require_relative "test/support/widen_recording_studio_requirement"

# Specify your gem's dependencies in recording_studio_agents.gemspec
gemspec

# GitHub-only gems. The gemspec pins the versions; these lines give Bundler a source.
# Tag v0.1.354 matches the dummy. FloatingFrame shipped in that tag.
# API 0.20 and Oauth 0.21.6 require flat_pack >= 0.1.341.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.354"
gem "recording_studio", ">= 6.1.0", github: "bowerbird-app/RecordingStudio", tag: "v6.1.0"
gem "recording_studio_ai", github: "bowerbird-app/RecordingStudio_AI", tag: "v0.21.2"
gem "recording_studio_api", github: "bowerbird-app/RecordingStudio_api", tag: "v0.22.1"
# API 0.22.1 depends on these GitHub-only gems.
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.20.0"
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons", tag: "v0.2.0"
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v4.1.0"
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.11.3"
# AI 0.21.2 depends on Logs, which is GitHub-only. v0.7.0 requires metrics ~> 0.6.1
# and rejects metrics 0.7.0. v0.7.1 allows metrics >= 0.6.1, < 1.0.
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.7.1"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.7.0"
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
