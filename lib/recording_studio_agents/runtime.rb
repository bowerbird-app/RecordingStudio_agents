# frozen_string_literal: true

module RecordingStudioAgents
  class Runtime
    def initialize(program:, ledger:, invocation:)
      @program = program
      @ledger = ledger
      @invocation = invocation
    end

    def call(request:, run:, lease_token:, plan: nil)
      state = WorkingState.load(run.try(:working_state_json))
      state, = StateDelta.apply(state, { "set_goal" => request.task_input.goal }) if state.goal.to_s.empty?
      menu = ActionMenu.new.restore_terminal(state.data["candidate_index"])
      if plan && state.counter("reasoner_calls").zero?
        state, menu = accept_plan(request, run, lease_token, state, plan, replan: false)
      end

      guard = 0
      loop do
        guard += 1
        if guard > configuration.maximum_steps + configuration.maximum_reasoner_calls + 5
          return fail_run(run, lease_token, "maximum_steps", false)
        end

        @ledger.renew_lease!(run: run, lease_token: lease_token)
        run.agent_steps.reset
        state = shrink(request, run, lease_token, state)
        resumed = resume_open_step(request, run, lease_token, state)
        return resumed if resumed.is_a?(Results::Blocked) || resumed.is_a?(Results::Failed)

        state, menu = resumed if resumed.is_a?(Array)

        steps = run.agent_steps.count
        if Signals.over_budget?(state: state, steps: steps, configuration: configuration, started_at: run.started_at)
          code = Signals.budget_code(
            state: state, steps: steps, configuration: configuration, started_at: run.started_at
          )
          return fail_run(run, lease_token, code, false)
        end

        if menu.actionable.empty?
          if state.counter("replans") >= configuration.maximum_replans
            return fail_run(run, lease_token, "maximum_replans",
                            false)
          end
          if state.counter("reasoner_calls") >= configuration.maximum_reasoner_calls
            return fail_run(run, lease_token, "maximum_reasoner_calls",
                            false)
          end

          state, menu = replan(request, run, lease_token, state, menu)
          next
        end

        if Signals.repeated_digest?(state) || state.data["no_progress_streak"].to_i >= Signals::REPEAT_LIMIT
          @ledger.note_activity!(run: run, lease_token: lease_token, kind: "stuck_detected",
                                 data: { "sequence" => steps })
          if state.counter("replans") >= configuration.maximum_replans
            return fail_run(run, lease_token, "maximum_replans",
                            false)
          end

          state, menu = replan(request, run, lease_token, state, menu)
          next
        end

        if state.criteria_met? && menu.actionable.any?(&:deliver?)
          return finish(request, run, lease_token, state, menu.actionable.find(&:deliver?))
        end
        return finish(request, run, lease_token, state, menu.actionable.first) if menu.answer_plan

        verdict, state = decide(request, run, lease_token, state, menu, steps)
        if verdict.fail?
          return fail_run(run, lease_token, "decision_failed",
                          verdict.probabilities["retryable"] == true)
        end

        if verdict.reason?
          if state.counter("replans") >= configuration.maximum_replans
            return fail_run(run, lease_token, "maximum_replans",
                            false)
          end

          state, menu = replan(request, run, lease_token, state, menu)
          next
        end
        return finish(request, run, lease_token, state, menu.fetch(verdict.candidate_id)) if verdict.finish?
        return handoff(run, lease_token, menu.fetch(verdict.candidate_id), verdict) if verdict.handoff?

        acted = perform(request, run, lease_token, state, menu, verdict)
        return acted if acted.is_a?(Results::Blocked) || acted.is_a?(Results::Failed)

        state, menu = acted
      end
    end

    private

    def configuration
      RecordingStudioAgents.configuration
    end

    def accept_plan(request, run, lease_token, state, response, replan:)
      data = response.structured_data.is_a?(Hash) ? response.structured_data.stringify_keys : {}
      menu = ActionMenu.admit(
        data["action_candidates"],
        program: @program,
        refused_digests: state.data["refused_digests"]
      )
      menu = keep_answer_available(menu, state)
      state, compacted = StateDelta.apply(state, {
                                            "replace_plan" => Array(data["plan"]),
                                            "replace_criteria" => Array(data["success_criteria"]),
                                            "set_current_objective" => data["current_objective"],
                                            "replace_candidate_index" => menu.index,
                                            "increment" => { "reasoner_calls" => 1, "replans" => (replan ? 1 : 0) }
                                          })
      state = remember_compaction(state, compacted)
      state = shrink(request, run, lease_token, state)
      @ledger.checkpoint!(
        run: run, lease_token: lease_token, state: state,
        step: step_attributes(
          run, "completed", "reason", nil,
          observation_summary: data["current_objective"].to_s,
          ai_run_id: response.try(:run)&.id
        ),
        activities: replan ? [%w[replanned reasoner_requested]] : [%w[reasoner_requested]]
      )
      if compacted
        @ledger.note_activity!(run: run, lease_token: lease_token, kind: "compacted",
                               data: { "sequence" => run.agent_steps.maximum(:sequence).to_i })
      end
      [state, menu]
    end

    def replan(request, run, lease_token, state, menu)
      prompt = ContextBuilder.for_reasoner(state: state, menu: menu, signals: signal_lines(state, run))
      response = Ai.plan(invocation: @invocation, run: run, lease_token: lease_token, prompt: prompt,
                         suffix: "reason-#{state.counter('reasoner_calls') + 1}")
      if response.respond_to?(:run) && response.run
        @ledger.attach_ai_run!(run: run, lease_token: lease_token,
                               ai_run: response.run)
      end
      unless response.respond_to?(:error) ? response.error.nil? : true
        raise response.error if response.error.respond_to?(:message)

        raise ContractError, "replanning failed"
      end

      accept_plan(request, run, lease_token, state, response, replan: state.counter("reasoner_calls").positive?)
    end

    def decide(_request, run, lease_token, state, menu, _steps)
      questions = Controller.questions(menu)
      return [Controller.verdict(:reason, nil, "no_candidates", {}), state] if questions.dig(:next_action,
                                                                                             :criteria).blank?

      response = Ai.decide(
        invocation: @invocation, run: run, lease_token: lease_token,
        state: ContextBuilder.for_decision(state: state, menu: menu, signals: signal_lines(state, run)),
        questions: questions,
        suffix: "decide-#{state.counter('controller_calls') + 1}"
      )
      verdict = if response.respond_to?(:success?) && !response.success?
                  Controller.failure_verdict(response.error, configuration: configuration,
                                                             reasoner_calls: state.counter("reasoner_calls"))
                else
                  Controller.interpret(response.answers, menu: menu, state: state, configuration: configuration)
                end
      state, = StateDelta.apply(state, { "increment" => { "controller_calls" => 1 } })
      @ledger.checkpoint!(
        run: run, lease_token: lease_token, state: state,
        step: step_attributes(
          run, "completed", "decide", verdict.candidate_id,
          controller_outcome: verdict.probabilities.merge("reason" => verdict.reason, "name" => verdict.name.to_s),
          ai_run_id: response.try(:run)&.id,
          progress_made: verdict.probabilities["progress_made"].to_f >= configuration.progress_probability
        ),
        activities: [%w[controller_evaluated]]
      )
      if response.respond_to?(:run) && response.run
        @ledger.attach_ai_run!(run: run, lease_token: lease_token,
                               ai_run: response.run)
      end
      [verdict, state]
    end

    def perform(request, run, lease_token, state, menu, verdict)
      candidate = menu.fetch(verdict.candidate_id)
      sequence = next_sequence(run)
      repeatable = repeatable_tool?(candidate)
      @ledger.checkpoint!(
        run: run, lease_token: lease_token, state: state,
        step: step_attributes(
          run, "started", "tool", candidate.id,
          tool_key: candidate.tool_key, tool_version: candidate.tool_version,
          argument_digest: candidate.argument_digest, repeatable: repeatable,
          sequence: sequence, controller_outcome: verdict.probabilities.merge("reason" => verdict.reason)
        ),
        activities: [%w[step_started]]
      )
      begin
        performance = Ai.perform_tool(
          invocation: @invocation, run: run, candidate: candidate, sequence: sequence, resume: false
        )
      rescue ConfigurationError => e
        return stop_for_tool_error(run, lease_token, state, sequence, e.message)
      end
      apply_performance(request, run, lease_token, state, menu, candidate, sequence, performance, verdict)
    end

    def resume_open_step(request, run, lease_token, state)
      step = run.agent_steps.order(:sequence).last
      return unless step

      if step.status == "awaiting_confirmation"
        candidate = candidate_from_step(step)
        begin
          performance = Ai.perform_tool(
            invocation: @invocation, run: run, candidate: candidate, sequence: step.sequence, resume: true
          )
        rescue ConfigurationError => e
          return stop_for_tool_error(run, lease_token, state, step.sequence, e.message)
        end
        menu = ActionMenu.new.restore_terminal(state.data["candidate_index"])
        return apply_performance(request, run, lease_token, state, menu, candidate, step.sequence, performance, nil)
      end

      return unless step.status == "started" && step.action_type == "tool"

      close_started_step(run, lease_token, state, step)
    end

    def apply_performance(request, run, lease_token, state, menu, candidate, sequence, performance, verdict)
      if performance.awaiting_confirmation?
        @ledger.checkpoint!(
          run: run, lease_token: lease_token, state: state,
          step: { sequence: sequence, status: "awaiting_confirmation" },
          activities: []
        )
        @ledger.commit_blocked!(run: run, lease_token: lease_token)
        return Results::Blocked.new(run: run.reload)
      end

      unless performance.success?
        summary = performance.error&.message.to_s
        state, = StateDelta.apply(state, {
                                    "add_failed" => [summary],
                                    "add_observations" => [{ "sequence" => sequence, "summary" => summary }],
                                    "add_attempted_digest" => candidate.argument_digest,
                                    "add_refused_digest" => refused_digest(candidate),
                                    "increment" => { "tool_actions" => 1 }
                                  })
        @ledger.checkpoint!(
          run: run, lease_token: lease_token, state: state,
          step: {
            sequence: sequence, status: "failed",
            observation_summary: summary,
            observation_digest: Digests.of(summary),
            recording_studio_ai_run_id: performance.run&.id
          },
          activities: [%w[step_completed]]
        )
        menu.consume(candidate.id)
        state, = StateDelta.apply(state, { "replace_candidate_index" => menu.index })
        return [state, menu]
      end

      summary = observation_summary(performance.result)
      previous = state.digest_of_progress
      delta = observation_delta(performance.result, sequence, summary, candidate.argument_digest)
      state, compacted = StateDelta.apply(state, delta)
      streak = state.digest_of_progress == previous ? state.data["no_progress_streak"].to_i + 1 : 0
      state, = StateDelta.apply(state, { "set_no_progress_streak" => streak, "increment" => { "tool_actions" => 1 } })
      unless repeatable_tool?(candidate)
        state, = StateDelta.apply(state,
                                  { "add_refused_digest" => candidate.argument_digest })
      end
      state = remember_compaction(state, compacted)
      menu.consume(candidate.id)
      state, = StateDelta.apply(state, { "replace_candidate_index" => menu.index })
      state = shrink(request, run, lease_token, state)
      @ledger.checkpoint!(
        run: run, lease_token: lease_token, state: state,
        step: {
          sequence: sequence, status: "completed",
          observation_summary: summary,
          observation_digest: Digests.of(summary),
          progress_made: streak.zero?,
          controller_outcome: verdict&.probabilities,
          recording_studio_ai_run_id: performance.run&.id
        },
        activities: [%w[step_completed state_updated]]
      )
      if compacted
        @ledger.note_activity!(run: run, lease_token: lease_token, kind: "compacted",
                               data: { "sequence" => sequence })
      end
      [state, menu]
    end

    def close_started_step(run, lease_token, state, step)
      state, = StateDelta.apply(state, {
                                  "add_attempted_digest" => step.argument_digest,
                                  "add_refused_digest" => (step.repeatable ? nil : step.argument_digest),
                                  "increment" => { "tool_actions" => 1 }
                                })
      @ledger.checkpoint!(
        run: run, lease_token: lease_token, state: state,
        step: {
          sequence: step.sequence, status: "unresolved",
          observation_summary: "Interrupted before the tool finished."
        },
        activities: [%w[step_completed]]
      )
      [state, ActionMenu.new.restore_terminal(state.data["candidate_index"])]
    end

    def finish(_request, run, lease_token, state, candidate)
      response = Ai.synthesize(invocation: @invocation, run: run, lease_token: lease_token, state: state)
      if response.respond_to?(:run) && response.run
        @ledger.attach_ai_run!(run: run, lease_token: lease_token,
                               ai_run: response.run)
      end
      text = response.try(:text).to_s
      digest = Digests.of("text" => text)
      summary = text.strip
      summary = summary.empty? ? "Answered." : summary.byteslice(0, WorkingState::TEXT_LIMIT)
      @ledger.checkpoint!(
        run: run, lease_token: lease_token, state: state,
        step: step_attributes(
          run, "completed", "deliver", candidate&.id,
          observation_summary: summary, ai_run_id: response.try(:run)&.id
        ),
        activities: [%w[step_completed]]
      )
      @ledger.commit_succeeded!(run: run, lease_token: lease_token, digest: digest)
      Results::Completed.new(run: run.reload, output: Output.new(text: text, data: nil, citations: []))
    end

    def handoff(run, lease_token, candidate, verdict)
      target = Reference.new(key: candidate.handoff_key, version: candidate.handoff_version)
      @ledger.note_handoff!(agent_run_id: run.id, ai_run_id: nil, target: target, lease_token: lease_token)
      @ledger.checkpoint!(
        run: run, lease_token: lease_token, state: WorkingState.load(run.reload.working_state_json),
        step: step_attributes(
          run, "completed", "handoff", candidate.id,
          controller_outcome: verdict.probabilities.merge("reason" => verdict.reason)
        ),
        activities: []
      )
      @ledger.commit_handoff!(run: run, lease_token: lease_token, target: target)
      Results::HandoffRequested.new(run: run.reload, request: HandoffRequest.new(target: target))
    end

    def fail_run(run, lease_token, code, retryable)
      decision = code == "decision_failed"
      failure = Failure.new(
        category: decision ? "provider_error" : "budget",
        code: code,
        message: decision ? "Controller decision failed." : "Agent run stopped at #{code}.",
        retryable: retryable
      )
      @ledger.commit_failed!(run: run, lease_token: lease_token, failure: failure)
      Results::Failed.new(run: run.reload, failure: failure)
    end

    def remember_compaction(state, compacted)
      return state unless compacted

      updated, = StateDelta.apply(state, { "increment" => { "compactions" => 1 } })
      updated
    end

    def shrink(_request, run, lease_token, state)
      return state unless state.bytesize > configuration.maximum_working_state_bytes
      return state if state.counter("compactions") >= 3

      response = Ai.compact_state(
        invocation: @invocation, run: run, lease_token: lease_token, state: state,
        suffix: "compact-#{state.counter('compactions') + 1}"
      )
      data = response.try(:structured_data)
      return state unless data.is_a?(Hash)

      updated, changed = StateDelta.apply(state, data.merge("increment" => { "compactions" => 1 }))
      if changed
        @ledger.note_activity!(run: run, lease_token: lease_token, kind: "compacted",
                               data: { "sequence" => run.agent_steps.maximum(:sequence).to_i })
      end
      updated
    rescue StandardError
      state
    end

    def observation_summary(result)
      case result
      when String then result.byteslice(0, WorkingState::TEXT_LIMIT)
      when Hash
        text = result["summary"] || result[:summary]
        return text.to_s.byteslice(0, WorkingState::TEXT_LIMIT) if text

        describe_hash(result).byteslice(0, WorkingState::TEXT_LIMIT)
      else
        result.class.name
      end
    end

    def describe_hash(result)
      pages = result["pages"] || result[:pages]
      if pages.is_a?(Array)
        titles = pages.filter_map { |page| page_title(page) }
        return "No pages." if titles.empty?

        return "Pages: #{titles.join(', ')}"
      end

      title = result["title"] || result[:title]
      return "Found #{title}." if title

      "keys: #{result.keys.map(&:to_s).sort.join(', ')}"
    end

    def page_title(page)
      return unless page.is_a?(Hash)

      page["title"] || page[:title]
    end

    def stop_for_tool_error(run, lease_token, state, sequence, message)
      @ledger.checkpoint!(
        run: run, lease_token: lease_token, state: state,
        step: {
          sequence: sequence, status: "failed",
          observation_summary: message,
          observation_digest: Digests.of(message)
        },
        activities: [%w[step_completed]]
      )
      failure = Failure.new(category: "configuration", code: "tool_unavailable", message: message, retryable: false)
      @ledger.commit_failed!(run: run, lease_token: lease_token, failure: failure)
      Results::Failed.new(run: run.reload, failure: failure)
    end

    def observation_delta(result, sequence, summary, digest)
      findings = result.is_a?(Hash) ? Array(result["findings"] || result[:findings]) : []
      completed = result.is_a?(Hash) ? Array(result["completed"] || result[:completed]) : []
      {
        "add_findings" => findings,
        "add_completed" => completed,
        "add_observations" => [{ "sequence" => sequence, "summary" => summary }],
        "add_attempted_digest" => digest,
        "meet_criteria" => result.is_a?(Hash) ? Array(result["meet_criteria"] || result[:meet_criteria]) : []
      }
    end

    def candidate_from_step(step)
      ActionMenu::Candidate.new(
        id: step.candidate_id.to_s,
        type: "tool",
        purpose: step.observation_summary.to_s.presence || "Resume the tool",
        tool_key: step.tool_key,
        tool_version: step.tool_version,
        argument_digest: step.argument_digest,
        arguments: nil
      )
    end

    def refused_digest(candidate)
      return if repeatable_tool?(candidate)

      candidate.argument_digest
    end

    def repeatable_tool?(candidate)
      definition = RecordingStudioAI.tools.fetch(candidate.tool_key, version: candidate.tool_version)
      return false unless definition

      definition.idempotent && !definition.destructive && !definition.requires_confirmation
    rescue StandardError
      false
    end

    def step_attributes(run, status, action_type, candidate_id, tool_key: nil, tool_version: nil,
                        argument_digest: nil, observation_summary: nil, controller_outcome: nil,
                        ai_run_id: nil, progress_made: nil, repeatable: false, sequence: nil)
      {
        sequence: sequence || next_sequence(run),
        status: status,
        action_type: action_type,
        candidate_id: candidate_id,
        tool_key: tool_key,
        tool_version: tool_version,
        argument_digest: argument_digest,
        observation_summary: observation_summary,
        observation_digest: observation_summary && Digests.of(observation_summary),
        progress_made: progress_made,
        controller_outcome: controller_outcome,
        recording_studio_ai_run_id: ai_run_id,
        repeatable: repeatable
      }
    end

    def next_sequence(run)
      run.agent_steps.maximum(:sequence).to_i + 1
    end

    def keep_answer_available(menu, state)
      return menu unless observations_present?(state)
      return menu if answer_available?(menu)

      menu.add(
        ActionMenu::Candidate.new(id: "answer", type: "deliver", purpose: "Answer from the current observations")
      )
    end

    def answer_available?(menu)
      menu.actionable.any?(&:deliver?)
    end

    def observations_present?(state)
      Array(state.data["recent_observations"]).any?
    end

    def signal_lines(state, run)
      Signals.lines(state: state, steps: run.agent_steps.count, configuration: configuration,
                    started_at: run.started_at)
    end
  end
end
