# frozen_string_literal: true

class PlaygroundCatalog
  Entry = Data.define(:key, :version, :name, :tools, :required_skills) do
    def token
      "#{key}@#{version}"
    end
  end

  Option = Data.define(:key, :version, :name) do
    def token
      "#{key}@#{version}"
    end
  end

  def self.entries
    RecordingStudioAgents.agents.all.map do |definition|
      Entry.new(
        key: definition.key,
        version: definition.version,
        name: definition.name,
        tools: options_for(definition.tools, RecordingStudioAI.tools),
        required_skills: options_for(definition.skills, RecordingStudioAgents.skills)
      )
    end
  end

  def self.skills
    RecordingStudioAgents.skills.all.map do |definition|
      Option.new(key: definition.key, version: definition.version, name: definition.name)
    end
  end

  def self.options_for(references, registry)
    references.map do |reference|
      named = registry.fetch(reference.key, version: reference.version)
      Option.new(key: reference.key, version: reference.version, name: named.name)
    end
  end
  private_class_method :options_for
end
