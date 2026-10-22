# frozen_string_literal: true

# Recording Studio 5.0.0 is a major bump. Every published addon gemspec that
# depends on recording_studio still uses a pessimistic 4.x cap (`~> 4.2` or
# `~> 4.7`), which does not allow 5.0.0. Checked on GitHub, including the
# newest tag of each gem (2026-10-22):
#
#   recording_studio_ai            v0.15.1 through v0.18.0
#   recording_studio_accessible    v0.20.0 through v0.21.0
#   recording_studio_trashable     v0.11.1 and v0.11.2
#   recording_studio_api           v0.11.4 through v0.15.0
#   recording_studio_mcp           v0.19.1 through v0.21.0
#   recording_studio_metrics       v0.3.1 through v0.5.0
#   recording_studio_user          v0.24.0 through v0.25.1
#   recording_studio_oauth         v0.12.5 through v0.13.2
#   recording_studio_root_switchable v0.9.5 and v0.9.6
#   recording_studio_cache         v0.5.1
#   recording_studio_site_settings v0.5.1
#   recording_studio_attachable    v0.20.1
#   recording_studio_logs          main (no 5.x tag)
#
# recording_studio_admin does not depend on recording_studio directly.
# There is no higher tag to pin. This file lets the dummy app resolve
# Recording Studio v5.0.0 against those tags. Delete it when an addon tag
# depends on recording_studio >= 5.
module RecordingStudioAgents
  module BundlerRecordingStudio5
    def add_dependency(name, *requirements)
      super(name, *RecordingStudioAgents::BundlerRecordingStudio5.recording_studio_requirement(name, requirements))
    end

    def add_runtime_dependency(name, *requirements)
      super(name, *RecordingStudioAgents::BundlerRecordingStudio5.recording_studio_requirement(name, requirements))
    end

    def self.recording_studio_requirement(name, requirements)
      return requirements unless name.to_s == "recording_studio"
      return requirements if requirements.empty?
      return requirements if Gem::Requirement.new(requirements).satisfied_by?(Gem::Version.new("5.0.0"))

      [">= 4.2", "< 6"]
    end
  end
end

Gem::Specification.prepend(RecordingStudioAgents::BundlerRecordingStudio5)
