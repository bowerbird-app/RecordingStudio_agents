# frozen_string_literal: true

module RecordingStudioAgents
  class ContextBuilder
    def self.for_decision(state:, menu:, signals:)
      sections(state, menu, signals).join("\n\n")
    end

    def self.for_reasoner(state:, menu:, signals:)
      [
        "Revise the plan and action candidates from the current state.",
        "Return only the structured fields. Do not invent a tool call the runtime did not ask for.",
        sections(state, menu, signals).join("\n\n")
      ].join("\n\n")
    end

    def self.for_synthesis(state:)
      [
        "Write the final answer from the current state.",
        sections(state, ActionMenu.new, [])
      ].join("\n\n")
    end

    def self.sections(state, menu, signals)
      data = state.data
      [
        labeled("GOAL", data["goal"]),
        labeled("SUCCESS CRITERIA", criteria(data["success_criteria"])),
        labeled("CURRENT PLAN", lines(data["plan"])),
        labeled("CURRENT OBJECTIVE", data["current_objective"]),
        labeled("IMPORTANT FINDINGS", lines(data["findings"])),
        labeled("COMPLETED WORK", lines(data["completed_work"])),
        labeled("FAILED APPROACHES", lines(data["failed_work"])),
        labeled("OPEN QUESTIONS", lines(data["open_questions"])),
        labeled("RECENT OBSERVATIONS", observations(data["recent_observations"])),
        labeled("AVAILABLE ACTION CANDIDATES", candidates(menu)),
        labeled("SIGNALS", Array(signals).join("\n"))
      ]
    end

    def self.labeled(title, body)
      "#{title}\n#{body.to_s.strip.empty? ? "None" : body}"
    end

    def self.lines(values)
      Array(values).join("\n")
    end

    def self.criteria(values)
      Array(values).map { |item| "#{item['id']}: #{item['text']} (#{item['met'] ? 'met' : 'open'})" }.join("\n")
    end

    def self.observations(values)
      Array(values).map { |item| "#{item['sequence']}. #{item['summary']}" }.join("\n")
    end

    def self.candidates(menu)
      menu.actionable.map { |candidate|
        detail = candidate.tool? ? "#{candidate.tool_key} v#{candidate.tool_version}" : candidate.type
        "#{candidate.id}: #{detail}. #{candidate.purpose}"
      }.join("\n")
    end
  end
end
