# frozen_string_literal: true

module RecordingStudioAgents
  class Controller
    Verdict = Data.define(:name, :candidate_id, :reason, :probabilities) do
      def finish?
        name == :finish
      end

      def reason?
        name == :reason
      end

      def tool?
        name == :tool
      end

      def handoff?
        name == :handoff
      end

      def fail?
        name == :fail
      end
    end

    def self.questions(menu)
      criteria = menu.actionable.to_h { |candidate| [candidate.id, choice_text(candidate)] }
      {
        progress_made: {
          type: :noul,
          instructions: "Did the latest step make meaningful progress toward the success criteria?"
        },
        finished: {
          type: :noul,
          instructions: "Does the current state satisfy the success criteria?"
        },
        stuck: {
          type: :noul,
          instructions: "Does the current state look stuck or repetitive, beyond the mechanical signals listed?"
        },
        needs_reasoning: {
          type: :noul,
          instructions: "Does choosing the next useful action require a new plan?"
        },
        next_action: {
          type: :choice,
          instructions: "Which listed action id should happen next?",
          criteria: criteria
        }
      }
    end

    def self.choice_text(candidate)
      text = if candidate.tool?
               "#{candidate.tool_key} v#{candidate.tool_version}. #{candidate.purpose}"
             else
               candidate.purpose
             end
      text.byteslice(0, 240)
    end

    def self.completion_questions
      {
        finished: {
          type: :noul,
          instructions: "Can the goal be answered from the current observations?"
        },
        stuck: {
          type: :noul,
          instructions: "Does the current state look stuck or repetitive, beyond the mechanical signals listed?"
        }
      }
    end

    def self.interpret_completion(answers, configuration:)
      finished = probability(answers, :finished)
      stuck = probability(answers, :stuck)
      probabilities = { "finished" => finished, "stuck" => stuck }
      if finished >= configuration.finished_probability && stuck < configuration.stuck_probability
        return verdict(:finish, nil, "observations_answer_the_goal", probabilities)
      end

      verdict(:reason, nil, "observations_insufficient", probabilities)
    end

    def self.interpret(answers, menu:, state:, configuration:)
      finished = probability(answers, :finished)
      stuck = probability(answers, :stuck)
      needs = probability(answers, :needs_reasoning)
      progress = probability(answers, :progress_made)
      choice = answers[:next_action]
      selected = choice&.choice&.to_s
      margin = choice_margin(choice)
      probabilities = {
        "finished" => finished,
        "stuck" => stuck,
        "needs_reasoning" => needs,
        "progress_made" => progress,
        "choice_margin" => margin,
        "choice" => selected
      }

      if finished >= configuration.finished_probability && stuck < configuration.stuck_probability &&
         (menu.deliver?(selected) || state.criteria_met?)
        return verdict(:finish, selected, "finished", probabilities)
      end

      uncertain = stuck >= configuration.stuck_probability ||
                  needs >= configuration.needs_reasoning_probability ||
                  margin < configuration.choice_margin
      return verdict(:reason, nil, "uncertain", probabilities) if uncertain
      return verdict(:reason, nil, "missing_choice", probabilities) if selected.nil? || !menu.include?(selected)

      candidate = menu.fetch(selected)
      if candidate.deliver?
        return verdict(:finish, selected, "deliver", probabilities) if finished >= configuration.finished_probability

        return verdict(:reason, nil, "deliver_below_threshold", probabilities)
      end
      return verdict(:handoff, selected, "handoff", probabilities) if candidate.handoff?

      verdict(:tool, selected, "selected", probabilities)
    end

    def self.failure_verdict(error, configuration:, reasoner_calls:)
      retryable = error.respond_to?(:retryable?) ? error.retryable? : false
      if reasoner_calls < configuration.maximum_reasoner_calls
        return verdict(:reason, nil, "decision_failed", { "error_code" => error&.code })
      end

      Verdict.new(name: :fail, candidate_id: nil, reason: "decision_failed", probabilities: {
                    "retryable" => retryable,
                    "error_code" => error&.code,
                    "error_category" => error&.category,
                    "error_message" => error&.message
                  })
    end

    def self.probability(answers, key)
      answer = answers[key]
      return 0.0 unless answer.respond_to?(:probability)

      answer.probability.to_f
    end

    def self.choice_margin(choice)
      return 1.0 unless choice.respond_to?(:probabilities)

      values = choice.probabilities.values.map(&:to_f).sort.reverse
      return 1.0 if values.length < 2

      values[0] - values[1]
    end

    def self.verdict(name, candidate_id, reason, probabilities)
      Verdict.new(name: name, candidate_id: candidate_id, reason: reason, probabilities: probabilities)
    end
  end
end
