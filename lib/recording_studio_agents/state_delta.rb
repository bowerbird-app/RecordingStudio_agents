# frozen_string_literal: true

module RecordingStudioAgents
  class StateDelta
    KEYS = %w[
      add_findings add_completed add_failed add_open_questions remove_open_questions
      set_current_objective meet_criteria add_observations replace_plan replace_criteria
      replace_findings replace_completed replace_failed replace_observations
      replace_candidate_index set_no_progress_streak add_attempted_digest add_refused_digest
      increment set_goal add_constraints set_deliver_followup
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
      if changes.key?("replace_criteria")
        data["success_criteria"] = merge_criteria(data["success_criteria"], changes["replace_criteria"])
      end
      replace_lists(data, changes)
      data["candidate_index"] = changes["replace_candidate_index"] if changes.key?("replace_candidate_index")
      data["success_criteria"] = close_criteria(data["success_criteria"], changes["meet_criteria"])
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
      data["deliver_followup"] = true if changes["set_deliver_followup"] == true
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

    CONTAINED_TEXT_MINIMUM = 12

    def self.merge_criteria(existing, incoming)
      rows = criteria_from(incoming)
      kept = Array(existing).select { |item| item.is_a?(Hash) }
      return rows if kept.empty?

      merged = kept.map(&:dup)
      rows.each do |row|
        next if merged.any? { |item| same_criterion?(item, row) }

        merged << row if merged.length < WorkingState::LIMITS["success_criteria"]
      end
      merged
    end

    def self.same_criterion?(existing, row)
      existing["id"].to_s == row["id"].to_s || existing["text"].to_s == row["text"].to_s
    end

    def self.close_criteria(criteria, references)
      rows = Array(criteria)
      ids = canonical_ids(rows, references)
      rows.map do |item|
        next item unless item.is_a?(Hash)
        next item if item["met"] == true || !ids.include?(item["id"].to_s)

        item.merge("met" => true)
      end
    end

    def self.canonical_ids(criteria, references)
      Array(references).flat_map { |reference| ids_named_by(criteria, reference.to_s.strip) }.uniq
    end

    def self.ids_named_by(criteria, reference)
      return [] if reference.empty?

      rows = Array(criteria).select { |item| item.is_a?(Hash) }
      exact = rows.select { |item| reference == item["id"].to_s || reference == item["text"].to_s }
      return exact.map { |item| item["id"].to_s } if exact.any?

      ids = rows.filter_map { |item| item["id"].to_s if id_prefix?(reference, item["id"].to_s) }
      longest = contained_criteria(rows, reference).max_by { |item| item["text"].to_s.length }
      ids << longest["id"].to_s if longest
      ids.uniq
    end

    def self.contained_criteria(rows, reference)
      rows.select { |item| text_contained?(reference, item["text"].to_s) }
    end

    def self.text_contained?(reference, text)
      return false if text.length < CONTAINED_TEXT_MINIMUM

      reference.include?(text)
    end

    def self.id_prefix?(reference, id)
      return false if id.empty?

      reference.start_with?("#{id}:")
    end

    def self.criteria_from(values)
      Array(values).filter_map.with_index do |item, index|
        text = criterion_text(item)
        next if text.empty?

        { "id" => criterion_id(item, index), "text" => text, "met" => false }
      end
    end

    def self.criterion_text(item)
      raw = item.is_a?(Hash) ? (item["text"] || item[:text]) : item
      raw.to_s.strip
    end

    def self.criterion_id(item, index)
      raw = item.is_a?(Hash) ? (item["id"] || item[:id]) : nil
      id = raw.to_s.strip
      id.empty? ? "criterion_#{index + 1}" : id
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
