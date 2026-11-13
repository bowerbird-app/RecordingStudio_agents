# frozen_string_literal: true

# These pinned gemspecs still reject recording_studio 6.1.0: Accessible (~> 4.7),
# Trashable (~> 4.7), Cache (~> 4.2), Attachable (~> 4.2), Site Settings (~> 4.2),
# and Icons (>= 6.3.0). Bundler evaluates them through Gem::Specification, so
# this rewrite runs before resolution. MCP 0.33.1 and Oauth 0.21.6 already allow
# 6.1.0 and API < 0.23, so this file does not touch recording_studio_api.
# The file is not packaged in the gem.
module WidenRecordingStudioRequirement
  def add_dependency(name, *requirements)
    super(name, *widened(name.to_s, requirements))
  end

  # Gem stubs alias this to the original add_dependency, which skips a prepend.
  def add_runtime_dependency(name, *requirements)
    add_dependency(name, *requirements)
  end

  private

  def widened(name, requirements)
    requirements = requirements.flatten
    return [">= 6.1.0"] if name == "recording_studio" && !allows?(requirements, "6.1.0")

    requirements
  end

  def allows?(requirements, version)
    Gem::Requirement.new(requirements).satisfied_by?(Gem::Version.new(version))
  rescue ArgumentError
    false
  end
end

unless Gem::Specification.ancestors.include?(WidenRecordingStudioRequirement)
  Gem::Specification.prepend(WidenRecordingStudioRequirement)
end
