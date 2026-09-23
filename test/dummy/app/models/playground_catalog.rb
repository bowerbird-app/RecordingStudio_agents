# frozen_string_literal: true

class PlaygroundCatalog
  Entry = Data.define(:key, :version, :name, :optional_skills, :packs) do
    def token
      "#{key}@#{version}"
    end

    def extra_help?
      optional_skills.any? || packs.any?
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
        optional_skills: options_for(definition.optional_skills, RecordingStudioAgents.skills),
        packs: options_for(definition.packs, RecordingStudioAgents.skill_packs)
      )
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
