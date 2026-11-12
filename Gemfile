# frozen_string_literal: true

source "https://rubygems.org"

# Rewrites a recording_studio requirement that rejects 6.1.0. See the file's comment.
# AI 0.20.0, Logs 0.7.1, and Metrics 0.7.0 already allow 6.1.0.
require_relative "test/support/widen_recording_studio_requirement"

# Specify your gem's dependencies in recording_studio_agents.gemspec
gemspec

# GitHub-only gems. The gemspec pins the versions; these lines give Bundler a source.
# Tag v0.1.354 matches the dummy. FloatingFrame shipped in that tag.
# API 0.20 and Oauth 0.21.5 require flat_pack >= 0.1.341.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.354"
gem "recording_studio", ">= 6.1.0", github: "bowerbird-app/RecordingStudio", tag: "v6.1.0"
gem "recording_studio_ai", github: "bowerbird-app/RecordingStudio_AI", tag: "v0.20.0"
# AI 0.20 depends on Logs, which is GitHub-only. v0.7.0 requires metrics ~> 0.6.1
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
