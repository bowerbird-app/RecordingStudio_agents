# frozen_string_literal: true

module RecordingStudioAgents
  class ObservationReducer
    SECRET = /secret|token|password|credential/i
    LONG_TEXT = 200
    LIST_KEYS = %w[add_findings add_completed add_failed add_open_questions meet_criteria].freeze
    SKIP_FIELDS = %w[findings completed meet_criteria pages summary].freeze

    def self.preview(result)
      { "summary" => summarize(result), "needs_model" => unstructured?(result) }
    end

    def self.summarize(result)
      return clip(result) if result.is_a?(String)
      return summarize_hash(result) if result.is_a?(Hash)

      result.class.name
    end

    def self.shareable(result)
      return result.map { |item| shareable(item) } if result.is_a?(Array)
      return result unless result.is_a?(Hash)

      result.each_with_object({}) do |(key, value), copy|
        next if secret?(key)

        copy[key.to_s] = shareable(value)
      end
    end

    def self.accept(data, result)
      return { "summary" => nil, "delta" => {} } unless data.is_a?(Hash)

      changes = data.stringify_keys
      { "summary" => clean_text(changes["summary"], result), "delta" => delta_from(changes, result) }
    end

    def self.fold(base, extra)
      extra.each_with_object(base.dup) { |(key, value), merged| write_change(merged, key, value) }
    end

    def self.summarize_hash(result)
      text = string_at(result, "summary")
      return clip(text) if text

      pages = result["pages"] || result[:pages]
      return page_summary(pages) if pages.is_a?(Array)

      title = string_at(result, "title")
      return clip("Found #{title}.") if title
      return clip(labeled_fields(result)) unless labeled_fields(result).empty?

      "No details."
    end

    def self.unstructured?(result)
      return false unless result.is_a?(Hash)
      return false if string_at(result, "summary") || (result["pages"] || result[:pages]).is_a?(Array)

      result.any? { |key, value| !secret?(key) && dropped?(value) }
    end

    def self.page_summary(pages)
      titles = pages.filter_map { |page| page_title(page) }
      titles.empty? ? "No pages." : "Pages: #{titles.join(', ')}"
    end

    def self.page_title(page)
      return unless page.is_a?(Hash)

      page["title"] || page[:title]
    end

    def self.labeled_fields(result)
      result.filter_map { |key, value| field_phrase(key, value) }.join(". ")
    end

    def self.field_phrase(key, value)
      name = key.to_s
      return if secret?(name) || SKIP_FIELDS.include?(name) || !scalar?(value)

      "#{name}: #{value}"
    end

    def self.dropped?(value)
      case value
      when String then value.bytesize > LONG_TEXT
      when Hash then true
      when Array then value.any? { |item| dropped?(item) }
      else false
      end
    end

    def self.scalar?(value)
      value.is_a?(Numeric) || value == true || value == false ||
        (value.is_a?(String) && value.bytesize <= LONG_TEXT)
    end

    def self.string_at(result, name)
      value = result[name] || result[name.to_sym]
      value if value.is_a?(String)
    end

    def self.secret?(key)
      key.to_s.match?(SECRET)
    end

    def self.delta_from(changes, result)
      delta = {}
      LIST_KEYS.each { |key| assign_list(delta, key, changes[key], result) }
      objective = clean_text(changes["set_current_objective"], result)
      delta["set_current_objective"] = objective if objective
      delta
    end

    def self.assign_list(delta, key, value, result)
      return unless value.is_a?(Array)

      items = value.filter_map { |item| clean_text(item, result) }
      delta[key] = items if items.any?
    end

    def self.clean_text(value, result)
      return unless value.is_a?(String)

      text = clip(redact(value, result)).strip
      text unless text.empty?
    end

    def self.redact(text, result)
      secret_values(result).reduce(text.to_s) { |copy, secret| copy.gsub(secret, "") }
    end

    def self.secret_values(result, found = [])
      case result
      when Hash then collect_secrets(result, found)
      when Array then result.each { |item| secret_values(item, found) }
      end
      found
    end

    def self.collect_secrets(result, found)
      result.each do |key, value|
        if secret?(key) && value.is_a?(String) && value.length >= 8
          found << value
        else
          secret_values(value, found)
        end
      end
    end

    def self.write_change(merged, key, value)
      if LIST_KEYS.include?(key)
        merged[key] = (Array(merged[key]) + Array(value)).map(&:to_s).uniq
      elsif key == "increment"
        merged["increment"] = (merged["increment"] || {}).merge(value)
      elsif !merged.key?(key)
        merged[key] = value
      end
    end

    def self.clip(text)
      text.to_s.byteslice(0, WorkingState::TEXT_LIMIT)
    end
  end
end
