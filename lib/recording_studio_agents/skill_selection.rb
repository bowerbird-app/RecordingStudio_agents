# frozen_string_literal: true

module RecordingStudioAgents
  class SkillSelection
    attr_reader :pack, :extra_skills

    def self.none
      new(pack: nil, extra_skills: [], pack_definition: nil)
    end

    def self.parse(definition:, pack: nil, extra_skills: {})
      extras = normalize_references(extra_skills || {})
      extras.each { |reference| assert_optional!(definition, reference) }

      pack_reference, pack_definition = resolve_pack(definition, pack)
      Array(pack_definition&.skills).each { |reference| assert_optional!(definition, reference) }

      new(pack: pack_reference, extra_skills: extras, pack_definition: pack_definition)
    end

    def initialize(pack:, extra_skills:, pack_definition:)
      @pack = pack
      @extra_skills = Array(extra_skills)
      @pack_definition = pack_definition
      freeze
    end

    def skill_references
      refs = []
      refs.concat(@pack_definition.skills) if @pack_definition
      refs.concat(extra_skills)
      refs.uniq
    end

    def empty?
      skill_references.empty?
    end

    def as_json
      skill_references.map { |reference| { "key" => reference.key, "version" => reference.version } }
    end

    def key_list
      skill_references.map { |reference| "#{reference.key}:#{reference.version}" }.join(",")
    end

    def self.normalize_references(map)
      map.to_h.map { |item_key, item_version| Reference.new(key: item_key, version: item_version) }
    end
    private_class_method :normalize_references

    def self.resolve_pack(definition, pack)
      return [nil, nil] if pack.nil? || (pack.respond_to?(:empty?) && pack.empty?)

      reference = pack_reference_for(definition, pack)
      unless definition.packs.include?(reference)
        raise ContractError,
              "agent #{definition.key} version #{definition.version} does not allow pack " \
              "#{reference.key} version #{reference.version}"
      end

      [reference, RecordingStudioAgents.skill_packs.fetch(reference.key, version: reference.version)]
    end
    private_class_method :resolve_pack

    def self.pack_reference_for(definition, pack)
      return pack if pack.is_a?(Reference)

      if pack.is_a?(Hash)
        raise ContractError, "pack must name one pack" unless pack.size == 1

        key, version = pack.first
        return Reference.new(key: key, version: version)
      end

      listed = definition.packs.find { |item| item.key == pack.to_s }
      raise ContractError, "agent #{definition.key} does not allow pack #{pack}" unless listed

      listed
    end
    private_class_method :pack_reference_for

    def self.assert_optional!(definition, reference)
      return if definition.optional_skills.include?(reference)

      raise ContractError,
            "#{reference.key} version #{reference.version} is not an optional skill on " \
            "agent #{definition.key} version #{definition.version}"
    end
    private_class_method :assert_optional!
  end
end
