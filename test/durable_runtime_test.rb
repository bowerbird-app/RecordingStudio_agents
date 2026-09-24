# frozen_string_literal: true

require "test_helper"

class DurableRuntimeTest < PersistenceTestCase
  Answer = Struct.new(:probability)
  Choice = Struct.new(:choice, :probabilities)
  Decision = Struct.new(:answers, :error, :run, keyword_init: true) do
    def success?
      error.nil?
    end
  end
  Performance = Struct.new(:status, :result, :error, :run, :argument_digest, keyword_init: true) do
    def success?
      status == "completed" && error.nil?
    end

    def awaiting_confirmation?
      status == "awaiting_confirmation"
    end
  end

  def test_twenty_tool_steps_keep_the_model_context_bounded
    register_librarian
    generated = []
    decided = []
    performed = []
    counts = { choice: 0, tool: 0 }
    generate = ->(**kwargs) { twenty_generate(kwargs, generated) }
    decide = ->(**kwargs) { twenty_decide(kwargs, decided, counts) }
    perform = ->(**kwargs) { twenty_perform(kwargs, performed, counts) }

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          assert_bounded_twenty(run_librarian("twenty-steps"), generated, decided)
        end
      end
    end
  end

  def test_a_dead_worker_does_not_repeat_a_finished_tool
    register_librarian
    retune_tool(:find_page, idempotent: false, destructive: true, read_only: false)
    notes = []
    phase = :first

    generate = ->(**kwargs) { crash_generate(kwargs) }
    decide = ->(**kwargs) { crash_decide(kwargs, phase, notes) }
    perform = ->(**kwargs) { crash_perform(kwargs, notes) }

    first = nil
    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          first = run_librarian("crash-resume")
          phase = :second
          second = run_librarian("crash-resume")

          assert_instance_of RecordingStudioAgents::Results::Failed, first
          assert_instance_of RecordingStudioAgents::Results::Completed, second
          assert_equal %w[note-1 note-2 note-3 recovery], notes
          assert_equal 1, second.run.agent_steps.where(status: "unresolved").count
          assert_equal 0, second.run.agent_steps.where(argument_digest: digest_for("note-3"), status: "completed").count
        end
      end
    end
  end

  def test_a_stale_lease_cannot_commit_the_run
    register_librarian
    RecordingStudioAI.stub(:generate, lambda { |**|
      run = RecordingStudioAgents::AgentRun.order(:id).last
      run.update!(lease_expires_at: 1.hour.ago)
      generation_response
    }) do
      assert_raises(RecordingStudioAgents::IdempotencyConflict) do
        run_librarian("stale-lease")
      end
    end

    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "stale-lease")
    refute_equal "succeeded", run.status
  end

  def test_a_second_worker_cannot_checkpoint_a_live_lease
    register_librarian
    ledger = RecordingStudioAgents::Persistence::RunLedger.new
    request = RecordingStudioAgents::Execution::Request.parse(
      task: task_input,
      root_recording: root,
      initiator: actor,
      execution_source: :job,
      idempotency_key: "two-workers"
    )
    program = RecordingStudioAgents::Programs::Compiler.compile(
      definition: RecordingStudioAgents.agents.fetch(:librarian, version: 1)
    )
    opening = ledger.open!(program: program, request: request)
    again = ledger.open!(program: program, request: request)

    assert_predicate again, :in_progress?
    ledger.renew_lease!(run: opening.run, lease_token: opening.lease_token)
    assert opening.run.reload.lease_expires_at > Time.current

    error = assert_raises(RecordingStudioAgents::IdempotencyConflict) do
      ledger.checkpoint!(
        run: opening.run,
        lease_token: "someone-else",
        state: RecordingStudioAgents::WorkingState.load({ "goal" => "Find Getting Started." }),
        step: { sequence: 1, status: "completed", action_type: "reason" }
      )
    end
    assert_match(/lease is no longer valid/, error.message)
    assert_equal 0, opening.run.agent_steps.count
  end

  def test_confirmation_pauses_and_resumes_the_same_step
    register_librarian
    retune_tool(:find_page, idempotent: false, destructive: true, read_only: false, requires_confirmation: true)
    calls = []
    generate = lambda { |**kwargs|
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "After the yes.", run_id: 60)
      else
        plan_response(candidates: 1, run_id: 61)
      end
    }
    decide = lambda { |**kwargs|
      if kwargs[:state].include?("obs-paused")
        decision(finished: 0.95, choice_id: "deliver", candidate_ids: ["deliver"])
      else
        decision(finished: 0.1, choice_id: "action_1", candidate_ids: %w[action_1 deliver])
      end
    }
    perform = lambda { |**kwargs|
      calls << [kwargs[:request_id], kwargs[:resume], kwargs[:arguments]]
      if kwargs[:resume]
        performance(summary: "obs-paused")
      else
        Performance.new(status: "awaiting_confirmation", result: nil, error: nil, run: Struct.new(:id).new(62))
      end
    }

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          paused = run_librarian("confirm-step")
          assert_instance_of RecordingStudioAgents::Results::Blocked, paused
          assert_equal "awaiting_confirmation", paused.run.status
          assert_nil paused.run.lease_token
          assert_equal "awaiting_confirmation", paused.run.agent_steps.order(:sequence).last.status

          resumed = run_librarian("confirm-step")
          assert_instance_of RecordingStudioAgents::Results::Completed, resumed
          assert_equal([false, true], calls.map { |call| call[1] })
          assert_equal calls[0][0], calls[1][0]
          assert_nil calls[1][2]
          assert_equal 1, resumed.run.agent_steps.where(action_type: "tool", status: "completed").count
          refute_includes resumed.run.working_state_json.to_json, "SECRET-ARGUMENT"
        end
      end
    end
  end

  def test_step_budget_is_not_the_provider_attempt_limit
    register_librarian
    previous = RecordingStudioAgents.configuration.maximum_steps
    generated = 0
    RecordingStudioAgents.configuration.maximum_steps = 1
    RecordingStudioAI.stub(:generate, lambda { |**_kwargs|
      generated += 1
      plan_response(candidates: 5, run_id: 70)
    }) do
      RecordingStudioAI.stub(:decide, ->(**) { flunk "decide should wait for a free step" }) do
        result = run_librarian("step-budget")
        assert_instance_of RecordingStudioAgents::Results::Failed, result
        assert_equal "maximum_steps", result.failure.code
        assert_equal "budget", result.failure.category
        assert_equal 1, generated
        assert_equal 0, result.run.agent_steps.where(action_type: "tool").count
        assert_equal 3, RecordingStudioAI.configuration.maximum_attempts
      end
    end
  ensure
    RecordingStudioAgents.configuration.maximum_steps = previous
  end

  def test_repeated_no_progress_stops_at_the_replan_budget
    register_librarian
    previous = RecordingStudioAgents.configuration.maximum_replans
    generated = 0
    RecordingStudioAgents.configuration.maximum_replans = 1
    RecordingStudioAI.stub(:generate, lambda { |**|
      generated += 1
      plan_response(candidates: 4, run_id: 80 + generated)
    }) do
      RecordingStudioAI.stub(:decide, lambda { |**kwargs|
        choice_id = kwargs[:state][/action_\d+/] || "deliver"
        decision(finished: 0.1, choice_id: choice_id, candidate_ids: [choice_id, "deliver"])
      }) do
        RecordingStudioAI.stub(:perform_tool, ->(**) { performance(summary: "same") }) do
          result = run_librarian("replan-budget")
          assert_instance_of RecordingStudioAgents::Results::Failed, result
          assert_equal "maximum_replans", result.failure.code
          assert_operator generated, :<=, 3
          assert result.run.run_activities.exists?(kind: "stuck_detected")
          assert result.run.run_activities.exists?(kind: "replanned")
        end
      end
    end
  ensure
    RecordingStudioAgents.configuration.maximum_replans = previous
  end

  def test_a_failed_decision_does_not_count_as_finished
    register_librarian
    previous = RecordingStudioAgents.configuration.maximum_reasoner_calls
    RecordingStudioAgents.configuration.maximum_reasoner_calls = 1
    error = RecordingStudioAI::Contracts::NormalizedError.new(
      category: "provider_unavailable",
      code: "decision_down",
      message: "Jev is down",
      retryable: true
    )
    RecordingStudioAI.stub(:generate, ->(**) { plan_response(candidates: 1, run_id: 81) }) do
      RecordingStudioAI.stub(:decide, ->(**) { Decision.new(answers: {}, error: error, run: nil) }) do
        result = run_librarian("decision-down")
        assert_instance_of RecordingStudioAgents::Results::Failed, result
        assert_equal "decision_failed", result.failure.code
        assert_equal "provider_error", result.failure.category
        assert_predicate result.failure, :retryable?
        refute_equal "succeeded", result.run.status
      end
    end
  ensure
    RecordingStudioAgents.configuration.maximum_reasoner_calls = previous
  end

  def test_thresholds_and_uncertainty_stay_inside_the_controller
    configuration = RecordingStudioAgents.configuration
    menu = menu_for("deliver" => :deliver, "search" => :tool)
    low = decision_answers(finished: 0.79, choice_id: "deliver", candidate_ids: %w[deliver search])
    verdict = RecordingStudioAgents::Controller.interpret(low, menu: menu, state: empty_state,
                                                               configuration: configuration)
    assert_predicate verdict, :reason?

    high = decision_answers(finished: 0.8, choice_id: "deliver", candidate_ids: %w[deliver search])
    finished = RecordingStudioAgents::Controller.interpret(high, menu: menu, state: empty_state,
                                                                 configuration: configuration)
    assert_predicate finished, :finish?

    tied = decision_answers(
      finished: 0.1,
      choice_id: "search",
      candidate_ids: %w[deliver search],
      probabilities: { "search" => 0.51, "deliver" => 0.49 }
    )
    uncertain = RecordingStudioAgents::Controller.interpret(tied, menu: menu, state: empty_state,
                                                                  configuration: configuration)
    assert_predicate uncertain, :reason?
    assert_equal "uncertain", uncertain.reason

    failure = RecordingStudioAgents::Controller.failure_verdict(
      Struct.new(:code, :category, :message, :retryable?).new("down", "provider_unavailable", "down", false),
      configuration: configuration,
      reasoner_calls: configuration.maximum_reasoner_calls
    )
    assert_predicate failure, :fail?
    refute_predicate failure, :finish?
  end

  def test_state_deltas_reject_unknown_keys_and_stay_bounded
    state = RecordingStudioAgents::WorkingState.load({ "goal" => "Stay" })
    assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents::StateDelta.apply(state, { "rewrite" => "everything" })
    end
    assert_equal "Stay", state.goal

    updated, changed = RecordingStudioAgents::StateDelta.apply(state, {
                                                                 "add_findings" => %w[Same Same],
                                                                 "add_attempted_digest" => nil,
                                                                 "add_observations" => [{ "sequence" => 4,
                                                                                          "summary" => "Saw it" }]
                                                               })
    assert_equal false, changed
    assert_equal ["Same"], updated.data["findings"]
    assert_equal [], updated.data["attempted_digests"]
    assert_equal [{ "sequence" => 4, "summary" => "Saw it" }], updated.data["recent_observations"]

    many, = RecordingStudioAgents::StateDelta.apply(state, {
                                                      "add_findings" => Array.new(30) { |index| "finding #{index}" },
                                                      "add_observations" => Array.new(9) do |index|
                                                        { "sequence" => index, "summary" => "obs #{index}" }
                                                      end
                                                    })
    assert_equal RecordingStudioAgents::WorkingState::LIMITS["findings"], many.data["findings"].length
    assert_equal RecordingStudioAgents::WorkingState::LIMITS["recent_observations"],
                 many.data["recent_observations"].length
  end

  def test_compaction_waits_for_the_size_limit
    state = RecordingStudioAgents::WorkingState.load({ "goal" => "Stay" })
    _, quiet = RecordingStudioAgents::StateDelta.apply(state, { "add_findings" => ["one"] })
    assert_equal false, quiet

    previous = RecordingStudioAgents.configuration.maximum_working_state_bytes
    RecordingStudioAgents.configuration.maximum_working_state_bytes = 80
    bulky = RecordingStudioAgents::WorkingState.load({
                                                       "goal" => "Stay",
                                                       "findings" => Array.new(8) do |index|
                                                         "finding #{index} #{'x' * 80}"
                                                       end
                                                     })
    compacted, changed = RecordingStudioAgents::StateDelta.apply(bulky, { "add_open_questions" => ["still open"] })
    assert_equal true, changed
    assert_operator compacted.data["findings"].length, :<=, bulky.data["findings"].length
    assert_includes compacted.data["goal"], "Stay"
  ensure
    RecordingStudioAgents.configuration.maximum_working_state_bytes = previous
  end

  def test_explicit_criteria_can_finish_without_another_reasoner_call
    register_librarian
    generated = []
    decided = 0
    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      generated << kwargs[:request_id].to_s
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "Criteria met.", run_id: 82)
      else
        plan_response(candidates: 1, run_id: 83)
      end
    }) do
      RecordingStudioAI.stub(:decide, lambda { |**|
        decided += 1
        decision(finished: 0.1, choice_id: "action_1", candidate_ids: %w[action_1 deliver])
      }) do
        RecordingStudioAI.stub(:perform_tool, ->(**) { performance(summary: "found", criteria: ["done"]) }) do
          result = run_librarian("criteria-done")
          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal 1, decided
          assert_equal(1, generated.count { |request_id| request_id.end_with?(":answer") })
          refute(generated.any? { |request_id| request_id.include?(":reason-") })
          assert result.run.agent_steps.exists?(action_type: "deliver", status: "completed")
        end
      end
    end
  end

  def test_a_disallowed_handoff_candidate_is_not_taken
    register_librarian
    RecordingStudioAgents.agents.register(
      key: :reviewer, version: 1, name: "Reviewer", description: "Reviews", instructions: "Review."
    )
    generated = 0
    previous_calls = RecordingStudioAgents.configuration.maximum_reasoner_calls
    RecordingStudioAgents.configuration.maximum_reasoner_calls = 1
    RecordingStudioAI.stub(:generate, lambda { |**|
      generated += 1
      plan_response(candidates: 0, extra: [handoff_candidate("stranger", 1)], run_id: 84)
    }) do
      result = run_librarian("deny-handoff")
      assert_instance_of RecordingStudioAgents::Results::Failed, result
      assert_nil result.run.handoff_agent_key
      assert_equal 1, generated
    end
  ensure
    RecordingStudioAgents.configuration.maximum_reasoner_calls = previous_calls
  end

  def test_an_allowlisted_handoff_stays_terminal
    RecordingStudioAgents.agents.register(
      key: :reviewer, version: 1, name: "Reviewer", description: "Reviews", instructions: "Review."
    )
    register_librarian(handoffs: { reviewer: 1 })
    RecordingStudioAI.stub(:generate, lambda { |**|
      plan_response(candidates: 0, extra: [handoff_candidate("reviewer", 1)], run_id: 85)
    }) do
      RecordingStudioAI.stub(:decide, lambda { |**|
        decision(finished: 0.1, choice_id: "handoff_reviewer", candidate_ids: ["handoff_reviewer"])
      }) do
        result = run_librarian("allow-handoff")
        assert_instance_of RecordingStudioAgents::Results::HandoffRequested, result
        assert_equal "reviewer", result.request.target.key
        assert_equal "handoff_requested", result.run.status
        assert_equal 0, RecordingStudioAgents::AgentRun.where(agent_key: "reviewer").count
      end
    end
  end

  def test_tool_allowlist_drops_a_candidate_the_program_did_not_grant
    register_librarian
    program = RecordingStudioAgents::Programs::Compiler.compile(
      definition: RecordingStudioAgents.agents.fetch(:librarian, version: 1)
    )
    menu = RecordingStudioAgents::ActionMenu.admit(
      [
        candidate("ok", "note-ok").merge("tool_key" => "find_page"),
        candidate("nope", "note-no").merge("tool_key" => "lookup_invoice")
      ],
      program: program,
      refused_digests: []
    )

    assert_equal ["ok"], menu.actionable.map(&:id)
    refute(menu.index.any? { |entry| entry.key?("arguments") })
  end

  private

  def run_librarian(idempotency_key)
    RecordingStudioAgents.agent(:librarian, version: 1).run(
      task: task_input,
      root_recording: root,
      initiator: actor,
      execution_source: :job,
      idempotency_key: idempotency_key
    )
  end

  def plan_response(candidates:, run_id:, extra: [])
    listed = Array.new(candidates) { |index| candidate("action_#{index + 1}", "note-#{index + 1}") }
    listed << { "id" => "deliver", "type" => "deliver", "purpose" => "Answer the goal" }
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: {
        "plan" => ["Look it up", "Answer"],
        "success_criteria" => [{ "id" => "done", "text" => "The page was found" }],
        "current_objective" => "Look it up",
        "action_candidates" => listed + extra
      },
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def candidate(id, note)
    {
      "id" => id,
      "type" => "tool",
      "purpose" => "Look #{note}",
      "tool_key" => "find_page",
      "tool_version" => 1,
      "arguments" => { "note" => note }
    }
  end

  def handoff_candidate(key, version)
    {
      "id" => "handoff_#{key}",
      "type" => "handoff",
      "purpose" => "Ask #{key}",
      "handoff_key" => key,
      "handoff_version" => version
    }
  end

  def twenty_generate(kwargs, generated)
    generated << kwargs
    if kwargs[:request_id].to_s.end_with?(":answer")
      generation_response(text: "The page is ready.", run_id: 50)
    else
      plan_response(candidates: 20, run_id: 7)
    end
  end

  def twenty_decide(kwargs, decided, counts)
    decided << kwargs
    counts[:choice] += 1
    number = counts[:choice]
    return decision(finished: 0.95, choice_id: "deliver", candidate_ids: ["deliver"]) if number > 20

    decision(finished: 0.1, choice_id: "action_#{number}", candidate_ids: ["action_#{number}", "deliver"])
  end

  def twenty_perform(kwargs, performed, counts)
    performed << kwargs
    counts[:tool] += 1
    performance(
      summary: format("observation-%02d", counts[:tool]),
      secret: "SECRET-ARGUMENT",
      finding: "found #{counts[:tool]}"
    )
  end

  def assert_bounded_twenty(result, generated, decided)
    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_equal "The page is ready.", result.output.text
    assert_equal "The page is ready.", result.run.agent_steps.find_by!(action_type: "deliver").observation_summary
    assert_operator result.run.agent_steps.where(action_type: "tool", status: "completed").count, :>=, 20
    assert_equal (1..result.run.agent_steps.maximum(:sequence)).to_a, ordered_sequences(result)
    assert_equal 1, legacy_plan_calls(generated, result)
    assert_equal [], generated.first[:custom_tools]
    refute passes_attempt_limit?(generated)
    assert_equal 3, RecordingStudioAI.configuration.maximum_attempts
    assert_equal 21, decided.length
    assert_equal %i[progress_made finished stuck needs_reasoning next_action], decided.first[:questions].keys
    assert decided.first[:questions][:next_action][:criteria].values.all?(&:nil?)
    refute_includes decided.last[:state], "observation-01"
    refute_includes decided.last[:state], "Look note-1\n"
    refute_includes decided.last[:state], "SECRET-ARGUMENT"
    assert_includes decided.last[:state], "observation-20"
    assert_operator decided.last[:state].bytesize, :<, 8_000
    assert_operator widest_state(decided), :<, decided.first[:state].bytesize + 4_000
    answer = answer_call(generated)
    refute_includes answer[:prompt], "observation-01"
    refute_includes answer[:prompt], "SECRET-ARGUMENT"
    stored = result.run.working_state_json.to_json + result.run.agent_steps.map(&:attributes).to_json
    refute_includes stored, "SECRET-ARGUMENT"
    refute_includes stored, "chain of thought"
    assert result.run.agent_steps.where.not(observation_digest: nil).any?
  end

  def ordered_sequences(result)
    result.run.agent_steps.order(:sequence).pluck(:sequence)
  end

  def legacy_plan_calls(generated, result)
    generated.count { |call| call[:request_id] == "recording-studio-agents:#{result.run.id}" }
  end

  def passes_attempt_limit?(generated)
    generated.any? { |call| call.key?(:maximum_attempts) }
  end

  def widest_state(decided)
    decided.map { |call| call[:state].bytesize }.max
  end

  def answer_call(generated)
    generated.find { |call| call[:request_id].to_s.end_with?(":answer") }
  end

  def crash_generate(kwargs)
    if kwargs[:request_id].to_s.end_with?(":answer")
      generation_response(text: "Recovered.", run_id: 90)
    elsif kwargs[:prompt].to_s.include?("Revise the plan")
      plan_response(candidates: 0, extra: [candidate("recovery", "recovery")], run_id: 91)
    else
      plan_response(candidates: 3, run_id: 92)
    end
  end

  def crash_decide(kwargs, phase, notes)
    return first_crash_decision(notes) if phase == :first
    return decision(finished: 0.95, choice_id: "deliver", candidate_ids: ["deliver"]) if notes.include?("recovery")
    return recovery_decision if kwargs[:state].include?("recovery:")

    decision(finished: 0.1, stuck: 0.1, needs: 0.9, choice_id: "deliver", candidate_ids: ["deliver"])
  end

  def first_crash_decision(notes)
    number = notes.length + 1
    decision(finished: 0.1, choice_id: "action_#{number}", candidate_ids: ["action_#{number}", "deliver"])
  end

  def recovery_decision
    decision(finished: 0.1, choice_id: "recovery", candidate_ids: %w[recovery deliver])
  end

  def crash_perform(kwargs, notes)
    note = kwargs[:arguments]["note"]
    notes << note
    raise "worker died" if note == "note-3" && notes.count("note-3") == 1

    performance(summary: "obs-#{note}", finding: note == "recovery" ? "recovered" : nil)
  end

  def decision(choice_id:, candidate_ids:, **scores)
    scores[:progress] = 0.8 unless scores.key?(:progress)
    Decision.new(
      answers: decision_answers(choice_id: choice_id, candidate_ids: candidate_ids, **scores),
      error: nil,
      run: Struct.new(:id).new(400)
    )
  end

  def decision_answers(choice_id:, candidate_ids:, **scores)
    finished = scores.fetch(:finished, 0.1)
    stuck = scores.fetch(:stuck, 0.05)
    needs = scores.fetch(:needs, 0.05)
    progress = scores.fetch(:progress, 0.2)
    probs = scores[:probabilities] || candidate_ids.to_h { |id| [id, id == choice_id ? 0.9 : 0.05] }
    {
      finished: Answer.new(finished),
      progress_made: Answer.new(progress),
      stuck: Answer.new(stuck),
      needs_reasoning: Answer.new(needs),
      next_action: Choice.new(choice_id, probs)
    }
  end

  def performance(summary:, secret: nil, criteria: [], finding: nil)
    result = { "summary" => summary, "meet_criteria" => criteria }
    result["findings"] = [finding] if finding
    result["secret"] = secret if secret
    Performance.new(status: "completed", result: result, error: nil, run: Struct.new(:id).new(500),
                    argument_digest: "digest")
  end

  def digest_for(note)
    Digest::SHA256.hexdigest(JSON.generate({ "note" => note }))
  end

  def empty_state
    RecordingStudioAgents::WorkingState.load({})
  end

  def menu_for(kinds)
    menu = RecordingStudioAgents::ActionMenu.new
    kinds.each do |id, type|
      menu.add(RecordingStudioAgents::ActionMenu::Candidate.new(
                 id: id,
                 type: type.to_s,
                 purpose: id.to_s,
                 arguments: type == :tool ? { "q" => "1" } : nil,
                 tool_key: "find_page",
                 tool_version: 1
               ))
    end
    menu
  end
end
