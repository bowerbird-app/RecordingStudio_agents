# frozen_string_literal: true

require_relative "lib/recording_studio_agents/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_agents"
  spec.version     = RecordingStudioAgents::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_agents"
  spec.summary     = "Reusable agents for Recording Studio, executed through Recording Studio AI"
  spec.description = "A Rails engine that registers skills, knowledge, and agents in code, then runs " \
                     "each task attempt through Recording Studio AI without copying model output."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"].reject do |path|
      path == ".cursor" || path.start_with?(".cursor/")
    end
  end

  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", "~> 4.2"
  spec.add_dependency "recording_studio_accessible", "~> 0.6"
  spec.add_dependency "recording_studio_admin", "~> 2.0"
  spec.add_dependency "recording_studio_ai", "~> 0.3"
end
