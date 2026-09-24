# frozen_string_literal: true

require "json"

module RecordingStudioAgents
  class WorkingState
    LIMITS = {
      "plan" => 12,
      "success_criteria" => 8,
      "findings" => 12,
      "completed_work" => 12,
      "failed_work" => 8,
      "open_questions" => 8,
      "recent_observations" => 5,
      "attempted_digests" => 40,
      "refused_digests" => 40,
      "candidate_index" => 12,
      "constraints" => 8
    }.freeze
    TEXT_LIMIT = 500
    FINDING_FLOOR = 4

    def self.load(raw)
      data = case raw
             when nil, "" then {}
             when String then JSON.parse(raw)
             when Hash then raw
             else
               raise ContractError, "working state must be a JSON object"
             end
      raise ContractError, "working state must be a JSON object" unless data.is_a?(Hash)

      new(normalize(data.stringify_keys))
    rescue JSON::ParserError
      raise ContractError, "working state must be a JSON object"
    end

    def self.normalize(data)
      unknown = data.keys - KNOWN_KEYS
      raise ContractError, "working state has unknown keys: #{unknown.join(', ')}" if unknown.any?

      {
        "goal" => clip(data["goal"]),
        "plan" => string_list(data["plan"], LIMITS["plan"]),
        "current_objective" => clip(data["current_objective"]),
        "success_criteria" => criteria(data["success_criteria"]),
        "findings" => string_list(data["findings"], LIMITS["findings"]),
        "completed_work" => string_list(data["completed_work"], LIMITS["completed_work"]),
        "failed_work" => string_list(data["failed_work"], LIMITS["failed_work"]),
        "open_questions" => string_list(data["open_questions"], LIMITS["open_questions"]),
        "recent_observations" => observations(data["recent_observations"]),
        "attempted_digests" => string_list(data["attempted_digests"], LIMITS["attempted_digests"]),
        "refused_digests" => string_list(data["refused_digests"], LIMITS["refused_digests"]),
        "candidate_index" => index(data["candidate_index"]),
        "constraints" => string_list(data["constraints"], LIMITS["constraints"]),
        "counters" => counters(data["counters"]),
        "no_progress_streak" => integer(data["no_progress_streak"])
      }
    end

    def self.string_list(value, limit)
      Array(value).filter_map { |item| clip(item) }.uniq.last(limit)
    end

    def self.clip(value)
      return if value.nil?

      text = value.to_s.strip
      return if text.empty?

      text.bytesize <= TEXT_LIMIT ? text : text.byteslice(0, TEXT_LIMIT)
    end

    def self.criteria(value)
      rows = Array(value).filter_map do |item|
        next unless item.is_a?(Hash)

        text = clip(item["text"] || item[:text])
        next if text.nil?

        id = clip(item["id"] || item[:id]) || text
        { "id" => id, "text" => text, "met" => item["met"] == true || item[:met] == true }
      end
      rows.uniq { |item| item["id"] }.last(LIMITS["success_criteria"])
    end

    def self.observations(value)
      Array(value).filter_map do |item|
        next unless item.is_a?(Hash)

        summary = clip(item["summary"] || item[:summary])
        next if summary.nil?

        { "sequence" => integer(item["sequence"] || item[:sequence]), "summary" => summary }
      end.last(LIMITS["recent_observations"])
    end

    def self.index(value)
      Array(value).filter_map do |item|
        next unless item.is_a?(Hash)

        id = clip(item["id"] || item[:id])
        type = (item["type"] || item[:type]).to_s
        next if id.nil? || !%w[tool deliver handoff].include?(type)

        {
          "id" => id,
          "type" => type,
          "tool_key" => item["tool_key"]&.to_s,
          "tool_version" => item["tool_version"]&.to_i,
          "argument_digest" => item["argument_digest"]&.to_s,
          "purpose" => clip(item["purpose"] || item[:purpose]),
          "handoff_key" => item["handoff_key"]&.to_s,
          "handoff_version" => item["handoff_version"]&.to_i
        }
      end.last(LIMITS["candidate_index"])
    end

    def self.counters(value)
      source = value.is_a?(Hash) ? value : {}
      COUNTER_KEYS.index_with { |key| integer(source[key] || source[key.to_sym]) }
    end

    def self.integer(value)
      number = Integer(value || 0)
      number.negative? ? 0 : number
    rescue ArgumentError, TypeError
      0
    end

    KNOWN_KEYS = %w[
      goal plan current_objective success_criteria findings completed_work failed_work
      open_questions recent_observations attempted_digests refused_digests candidate_index
      constraints counters no_progress_streak
    ].freeze
    COUNTER_KEYS = %w[reasoner_calls controller_calls tool_actions replans compactions].freeze

    attr_reader :data

    def initialize(data)
      @data = data
      freeze
    end

    def goal
      data["goal"]
    end

    def current_objective
      data["current_objective"]
    end

    def criteria_met?
      criteria = data["success_criteria"]
      criteria.any? && criteria.all? { |item| item["met"] }
    end

    def to_json(*)
      JSON.generate(data)
    end

    def bytesize
      to_json.bytesize
    end

    def counter(name)
      data["counters"][name.to_s].to_i
    end

    def digest_of_progress
      Digests.of(
        "findings" => data["findings"],
        "completed_work" => data["completed_work"],
        "criteria" => data["success_criteria"]
      )
    end
  end
end
