# frozen_string_literal: true

class PlaygroundLaunch < Data.define(
  :agent_key,
  :agent_version,
  :goal,
  :context,
  :pack,
  :extra_skills
)
  class Error < StandardError
  end

  Choice = Data.define(:key, :version)

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
      PlaygroundLaunch.new(
        agent_key: entry.key,
        agent_version: entry.version,
        goal: goal,
        context: context,
        pack: pack_for(entry),
        extra_skills: extras_for(entry)
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

    def extras_for(entry)
      Array(@params[:extra_skills]).flatten.map { |token| extra_choice(entry, token) }.uniq
    end

    def extra_choice(entry, token)
      choice = choice_from(token)
      allowed = choice && entry.optional_skills.any? { |skill| skill.key == choice.key && skill.version == choice.version }
      raise Error, "That extra help is not on this agent." unless allowed

      choice
    end

    def pack_for(entry)
      raw = @params[:pack]
      return if raw.blank?
      raise Error, "Pick one pack." if raw.is_a?(Array)

      choice = choice_from(raw)
      allowed = choice && entry.packs.any? { |pack| pack.key == choice.key && pack.version == choice.version }
      raise Error, "That pack is not on this agent." unless allowed

      choice
    end

    def choice_from(token)
      key, version = token.to_s.split("@", 2)
      return if key.blank? || version.blank?
      return unless version.match?(/\A[1-9]\d*\z/)

      Choice.new(key: key, version: Integer(version))
    end
  end
end
