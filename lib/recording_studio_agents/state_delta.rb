# frozen_string_literal: true

module RecordingStudioAgents
  class StateDelta
    KEYS = %w[
      add_findings add_completed add_failed add_open_questions remove_open_questions
      set_current_objective meet_criteria add_observations replace_plan replace_criteria
      replace_findings replace_completed replace_failed replace_observations
      replace_candidate_index set_no_progress_streak add_attempted_digest add_refused_digest
      increment set_goal add_constraints
    ].freeze

    def self.apply(state, delta)
      changes = coerce(delta)
      data = state.data.deep_dup
      apply_lists(data, changes)
      apply_scalars(data, changes)
      apply_increment(data, changes["increment"]) if changes.key?("increment")
      trimmed = WorkingState.load(data)
      compact(trimmed)
    end

    def self.coerce(delta)
      raise ContractError, "state delta must be an object" unless delta.is_a?(Hash)

      changes = delta.stringify_keys
      unknown = changes.keys - KEYS
      raise ContractError, "state delta has unknown keys: #{unknown.join(', ')}" if unknown.any?

      changes
    end

    def self.apply_lists(data, changes)
      append(data, "findings", changes["add_findings"])
      append(data, "completed_work", changes["add_completed"])
      append(data, "failed_work", changes["add_failed"])
      append(data, "open_questions", changes["add_open_questions"])
      append(data, "constraints", changes["add_constraints"])
      remove = Array(changes["remove_open_questions"]).map { |item| item.to_s.strip }
      data["open_questions"] = Array(data["open_questions"]).reject { |item| remove.include?(item) }
      data["plan"] = changes["replace_plan"] if changes.key?("replace_plan")
      data["success_criteria"] = criteria_from(changes["replace_criteria"]) if changes.key?("replace_criteria")
      replace_lists(data, changes)
      data["candidate_index"] = changes["replace_candidate_index"] if changes.key?("replace_candidate_index")
      meet = Array(changes["meet_criteria"]).map(&:to_s)
      data["success_criteria"] = Array(data["success_criteria"]).map do |item|
        meet.include?(item["id"].to_s) ? item.merge("met" => true) : item
      end
      Array(changes["add_observations"]).each do |item|
        summary, sequence = observation_from(item)
        data["recent_observations"] = Array(data["recent_observations"]) + [
          { "sequence" => sequence, "summary" => summary }
        ]
      end
      %w[attempted_digests refused_digests].each do |key|
        digest_key = "add_#{key.delete_suffix('s')}"
        next unless changes.key?(digest_key)

        digest = changes[digest_key].to_s.strip
        next if digest.empty?

        data[key] = Array(data[key]) + [digest]
      end
    end

    def self.apply_scalars(data, changes)
      data["current_objective"] = changes["set_current_objective"] if changes.key?("set_current_objective")
      data["goal"] = changes["set_goal"] if changes.key?("set_goal")
      data["no_progress_streak"] = changes["set_no_progress_streak"] if changes.key?("set_no_progress_streak")
    end

    def self.apply_increment(data, increments)
      raise ContractError, "state delta increment must be an object" unless increments.is_a?(Hash)

      unknown = increments.stringify_keys.keys - WorkingState::COUNTER_KEYS
      raise ContractError, "state delta has unknown counters: #{unknown.join(', ')}" if unknown.any?

      data["counters"] ||= {}
      increments.stringify_keys.each do |key, amount|
        data["counters"][key] = data["counters"][key].to_i + Integer(amount)
      end
    end

    REPLACE_LISTS = {
      "replace_findings" => "findings",
      "replace_completed" => "completed_work",
      "replace_failed" => "failed_work"
    }.freeze

    def self.replace_lists(data, changes)
      REPLACE_LISTS.each do |change_key, data_key|
        next unless changes.key?(change_key)

        data[data_key] = Array(changes[change_key]).filter_map { |item| item.to_s.strip.presence }
      end
      return unless changes.key?("replace_observations")

      data["recent_observations"] = Array(changes["replace_observations"]).filter_map do |item|
        replaced_observation(item)
      end
    end

    def self.replaced_observation(item)
      summary, sequence = observation_from(item)
      text = summary.to_s.strip
      return if text.empty?

      { "sequence" => sequence.to_i, "summary" => text }
    end

    def self.observation_from(item)
      return [item["summary"] || item[:summary], item["sequence"] || item[:sequence]] if item.is_a?(Hash)

      [item, 0]
    end

    def self.append(data, key, values)
      return if values.nil?

      data[key] = Array(data[key]) + Array(values)
    end

    def self.criteria_from(values)
      Array(values).map.with_index do |item, index|
        text = item.is_a?(Hash) ? (item["text"] || item[:text]) : item
        id = item.is_a?(Hash) ? (item["id"] || item[:id]) : "criterion_#{index + 1}"
        { "id" => id, "text" => text, "met" => false }
      end
    end

    def self.compact(state, limit: RecordingStudioAgents.configuration.maximum_working_state_bytes)
      data = state.data.deep_dup
      changed = false
      while JSON.generate(data).bytesize > limit && data["recent_observations"].length > 1
        data["recent_observations"].shift
        changed = true
      end
      while JSON.generate(data).bytesize > limit && data["findings"].length > WorkingState::FINDING_FLOOR
        data["findings"].shift
        changed = true
      end
      while JSON.generate(data).bytesize > limit && data["completed_work"].length > 1
        data["completed_work"].shift
        changed = true
      end
      if JSON.generate(data).bytesize > limit
        %w[findings completed_work failed_work plan].each do |key|
          data[key] = Array(data[key]).map { |item| item.to_s.byteslice(0, 120) }
        end
        changed = true
      end
      [WorkingState.load(data), changed]
    end
  end
end
