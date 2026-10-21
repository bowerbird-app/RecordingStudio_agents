# frozen_string_literal: true

require_relative "lib/recording_studio_agents/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_agents"
  spec.version     = RecordingStudioAgents::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_agents"
  spec.summary     = "Hosted agent chats for Recording Studio"
  spec.description = "Session ownership, retention, and provider cleanup for hosted agent chats."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_agents"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_agents/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"].reject do |path|
      path == ".cursor" || path.start_with?(".cursor/")
    end
  end

  spec.add_dependency "flat_pack", "~> 0.1"
  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", "~> 4.7"
  spec.add_dependency "recording_studio_ai", "~> 0.15.1"
end
