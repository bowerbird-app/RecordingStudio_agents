# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.143"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.2.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.7.0"
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin", tag: "v2.0.2"
gem "recording_studio_ai", github: "bowerbird-app/RecordingStudio_AI", tag: "v0.3.1"

gem "devise"
gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
  gem "simplecov", require: false
  gem "sqlite3", "~> 2.0"
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
