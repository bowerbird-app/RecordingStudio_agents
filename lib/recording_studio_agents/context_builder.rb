# frozen_string_literal: true

module RecordingStudioAgents
  class ContextBuilder
    def self.for_decision(state:, menu:, signals:)
      sections(state, menu, signals).join("\n\n")
    end

    def self.for_next_actions(state:, menu:, signals:)
      lines = [
        "Return the next one to three actions from the current state.",
        "A tool action needs type tool, tool_key, tool_version, purpose, and an arguments object.",
        "Leave the plan and the success criteria as they are."
      ]
      lines << sections(state, menu, signals).join("\n\n")
      lines.join("\n\n")
    end

    def self.for_reasoner(state:, menu:, signals:)
      lines = [
        "Revise the plan and action candidates from the current state.",
        "A tool candidate needs type tool, tool_key, tool_version, purpose, and an arguments object."
      ]
      if menu.actionable.empty?
        lines << "The last plan had no usable action candidates. Include a tool candidate or a deliver candidate."
      end
      lines << sections(state, menu, signals).join("\n\n")
      lines.join("\n\n")
    end

    def self.for_arguments(state:, candidate:, tool:)
      [
        "Return the arguments for #{candidate.tool_key} version #{candidate.tool_version}.",
        labeled("GOAL", state.goal),
        labeled("PURPOSE", candidate.purpose),
        labeled("TOOL", tool.description),
        "Use when: #{tool.use_when}",
        "Do not use when: #{tool.do_not_use_when}"
      ].join("\n\n")
    end

    def self.for_observation(state:, tool_label:, result:)
      data = state.data
      [
        "Summarize this tool result into a state delta.",
        "Add a finding, completed work, a failed approach, an open question, or a met criterion " \
        "only when the result supports it.",
        labeled("GOAL", data["goal"]),
        labeled("CURRENT OBJECTIVE", data["current_objective"]),
        labeled("SUCCESS CRITERIA", criteria(data["success_criteria"])),
        labeled("IMPORTANT FINDINGS", lines(data["findings"])),
        labeled("TOOL", tool_label),
        labeled("RESULT", JSON.generate(result))
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
      "#{title}\n#{body.to_s.strip.empty? ? 'None' : body}"
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
      menu.actionable.map do |candidate|
        detail = candidate.tool? ? "#{candidate.tool_key} v#{candidate.tool_version}" : candidate.type
        "#{candidate.id}: #{detail}. #{candidate.purpose}"
      end.join("\n")
    end
  end
end
