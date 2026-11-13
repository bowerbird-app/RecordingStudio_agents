# frozen_string_literal: true

# Sibling gemspecs in this repository still require recording_studio below 5,
# and MCP and Oauth still reject recording_studio_api 0.22. Bundler evaluates
# those gemspecs through Gem::Specification, so this rewrite runs before
# resolution. The file is not packaged in the gem.
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
    return [">= 0.22.1"] if name == "recording_studio_api" && !allows?(requirements, "0.22.1")

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
