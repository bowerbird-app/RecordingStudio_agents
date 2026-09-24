# frozen_string_literal: true

class PlaygroundLaunch < Data.define(
  :agent_key,
  :agent_version,
  :goal,
  :context,
  :pack,
  :extra_skills,
  :skills,
  :tools
)
  class Error < StandardError
  end

  Choice = Data.define(:key, :version) do
    def token
      "#{key}@#{version}"
    end
  end

  def self.parse(params, catalog:)
    Parser.new(params, catalog).parse
  end

  class Parser
    def initialize(params, catalog)
      @params = params
      @catalog = catalog
    end

    def parse
      entry = agent_entry
      chosen = chosen_for(entry)
      PlaygroundLaunch.new(
        agent_key: entry.key,
        agent_version: entry.version,
        goal: goal,
        context: context,
        pack: chosen[:pack],
        extra_skills: chosen[:extra_skills],
        skills: chosen[:skills],
        tools: chosen[:tools]
      )
    end

    private

    def agent_entry
      entry = @catalog.find { |item| item.token == @params[:agent].to_s }
      raise Error, "Pick an agent from the list." unless entry

      entry
    end

    def goal
      text = @params[:goal].to_s
      raise Error, "Write an instruction." if text.strip.empty?

      text
    end

    def context
      raw = @params[:context].to_s
      return {} if raw.strip.empty?

      parsed = JSON.parse(raw)
      raise Error, "That is not JSON." unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise Error, "That is not JSON."
    end

    def chosen_for(entry)
      return legacy_choices(entry) if @params[:choices].blank?

      skills = listed_choices(:skills) { |token| skill_choice(token) }
      tools = listed_choices(:tools) { |token| tool_choice(entry, token) }
      assert_skill_tools!(skills, tools)
      { pack: nil, extra_skills: [], skills: skills, tools: tools }
    end

    def legacy_choices(entry)
      { pack: pack_for(entry), extra_skills: extras_for(entry), skills: nil, tools: nil }
    end

    def listed_choices(key)
      Array(@params[key]).flatten.filter_map { |token| yield(token) if token.present? }.uniq
    end

    def skill_choice(token)
      choice = choice_from(token)
      raise Error, "Pick a skill from the list." unless choice

      RecordingStudioAgents.skills.fetch(choice.key, version: choice.version)
      choice
    rescue RecordingStudioAgents::Error
      raise Error, "Pick a skill from the list."
    end

    def tool_choice(entry, token)
      choice = choice_from(token)
      allowed = choice && entry.tools.any? { |tool| tool.key == choice.key && tool.version == choice.version }
      raise Error, "That tool is not on this agent." unless allowed

      choice
    end

    def assert_skill_tools!(skills, tools)
      chosen = tools.to_set { |tool| [ tool.key, tool.version ] }
      skills.each do |skill|
        definition = RecordingStudioAgents.skills.fetch(skill.key, version: skill.version)
        missing = definition.required_tools.find { |required| !chosen.include?([ required.key, required.version ]) }
        next unless missing

        tool = RecordingStudioAI.tools.fetch(missing.key, version: missing.version)
        raise Error, "#{definition.name} needs #{tool.name}."
      end
    end

    def extras_for(entry)
      listed_choices(:extra_skills) { |token| extra_choice(entry, token) }
    end

    def extra_choice(entry, token)
      choice = choice_from(token)
      raise Error, "That extra help is not on this agent." unless choice && optional_skill?(entry, choice)

      choice
    end

    def optional_skill?(entry, choice)
      RecordingStudioAgents.agents.fetch(entry.key, version: entry.version).optional_skills.any? do |skill|
        skill.key == choice.key && skill.version == choice.version
      end
    end

    def pack_for(entry)
      raw = @params[:pack]
      return if raw.blank?
      raise Error, "Pick one pack." if raw.is_a?(Array)

      choice = choice_from(raw)
      allowed = choice && pack_allowed?(entry, choice)
      raise Error, "That pack is not on this agent." unless allowed

      choice
    end

    def pack_allowed?(entry, choice)
      RecordingStudioAgents.agents.fetch(entry.key, version: entry.version).packs.any? do |pack|
        pack.key == choice.key && pack.version == choice.version
      end
    end

    def choice_from(token)
      key, version = token.to_s.split("@", 2)
      return if key.blank? || version.blank?
      return unless version.match?(/\A[1-9]\d*\z/)

      Choice.new(key: key, version: Integer(version))
    end
  end
end
