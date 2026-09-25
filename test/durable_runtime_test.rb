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

  def test_a_large_plan_keeps_only_three_tools
    register_librarian
    generated = []
    decided = []
    generate = lambda do |**kwargs|
      generated << kwargs
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "The page is ready.", run_id: 50)
      else
        plan_response(candidates: 20, run_id: 7)
      end
    end
    decide = lambda do |**kwargs|
      decided << kwargs
      criteria = kwargs[:questions].dig(:next_action, :criteria) || {}
      tool_id = criteria.keys.find { |id| id.to_s.start_with?("action_") }
      if tool_id
        decision(finished: 0.1, choice_id: tool_id, candidate_ids: criteria.keys)
      else
        decision(finished: 0.95, choice_id: "deliver", candidate_ids: criteria.keys)
      end
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, ->(**) { performance(summary: "saw a page", finding: "kept a page") }) do
          result = run_librarian("large-plan")
          criteria = decided.first[:questions][:next_action][:criteria]
          stored = result.run.working_state_json.to_json

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal 3, result.run.agent_steps.where(action_type: "tool", status: "completed").count
          assert_equal 1, legacy_plan_calls(generated, result)
          assert_equal %w[action_1 action_2 action_3 deliver], criteria.keys
          assert_includes criteria.fetch("action_1"), "find_page v1. Look note-1"
          refute_includes decided.first[:state], "Look note-20"
          refute_includes stored, "note-20"
          assert_equal ["Look it up", "Answer"], result.run.working_state_json["plan"]
          refute(generated.any? { |call| call[:request_id].to_s.include?(":next-") })
        end
      end
    end
  end

  def test_a_tool_chain_keeps_the_model_context_bounded
    register_librarian
    previous_calls = RecordingStudioAgents.configuration.maximum_reasoner_calls
    previous_steps = RecordingStudioAgents.configuration.maximum_steps
    RecordingStudioAgents.configuration.maximum_reasoner_calls = 40
    RecordingStudioAgents.configuration.maximum_steps = 120
    generated = []
    decided = []
    performed = []
    counts = { tools: 0 }
    generate = ->(**kwargs) { chain_generate(kwargs, generated) }
    decide = ->(**kwargs) { chain_decide(kwargs, decided, counts) }
    perform = ->(**kwargs) { chain_perform(kwargs, performed, counts) }

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          assert_bounded_chain(run_librarian("tool-chain"), generated, decided, performed)
        end
      end
    end
  ensure
    RecordingStudioAgents.configuration.maximum_reasoner_calls = previous_calls
    RecordingStudioAgents.configuration.maximum_steps = previous_steps
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

  def test_an_empty_plan_asks_for_a_usable_candidate
    register_librarian
    prompts = []
    generate = lambda do |**kwargs|
      prompts << kwargs
      if kwargs[:prompt].to_s.include?("no usable action candidates")
        plan_response(candidates: 1, run_id: 4)
      elsif kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "Done.", run_id: 5)
      else
        rejected_plan(6)
      end
    end
    decide = ->(**) { decision(finished: 0.95, choice_id: "deliver", candidate_ids: ["deliver"]) }
    perform = ->(**) { performance(summary: "unused") }

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("empty-plan")

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          plan_calls = prompts.reject do |call|
            request_id = call[:request_id].to_s
            request_id.end_with?(":answer") || request_id.include?(":arguments-")
          end
          assert_equal 2, plan_calls.length
          plan_calls.each do |call|
            assert_includes call[:system_instruction], "find_page version 1"
            assert_includes call[:system_instruction], "arguments object"
            assert_includes call[:system_instruction], "note (string, optional): Note to carry with the lookup."
            assert_equal [], call[:custom_tools]
          end
          type_schema = prompts.first[:schema].dig("properties", "action_candidates", "items", "properties", "type")
          assert_equal %w[tool deliver handoff], type_schema["enum"]
          assert(prompts.any? { |call| call[:prompt].to_s.include?("no usable action candidates") })
        end
      end
    end
  end

  def test_a_plan_lists_each_tools_required_parameters
    RecordingStudioAgents.agents.register(
      key: :reviewer, version: 1, name: "Reviewer", description: "Reviews", instructions: "Review."
    )
    register_librarian(handoffs: { reviewer: 1 })
    RecordingStudioAgents::Handoffs::Tool.register!
    retune_tool(
      :find_page,
      description: "Find a page by title.",
      use_when: "The task names a page.",
      do_not_use_when: "The task asks to rename a page.",
      returns: "The page recording id.",
      parameters: [
        { name: "title", type: "string", required: true, description: "Title of the page." },
        { name: "folder", type: "string", required: false, description: "Folder name when the title is shared." }
      ]
    )
    prompts = []
    plans = 0
    generate = lambda do |**kwargs|
      prompts << kwargs
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "Found it.", run_id: 8)
      else
        plans += 1
        plans == 1 ? rejected_plan(6) : plan_response(candidates: 1, run_id: 7)
      end
    end
    decide = ->(**) { decision(finished: 0.95, choice_id: "deliver", candidate_ids: %w[action_1 deliver]) }

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        result = run_librarian("tool-parameters")

        assert_instance_of RecordingStudioAgents::Results::Completed, result
        plan_calls = prompts.reject do |call|
          request_id = call[:request_id].to_s
          request_id.end_with?(":answer") || request_id.include?(":arguments-")
        end
        assert_equal 2, plan_calls.length
        assert_match(/:reason-/, plan_calls.last[:request_id])
        plan_calls.each do |call|
          instruction = call[:system_instruction]
          assert_includes instruction, "find_page version 1. Find a page by title."
          assert_includes instruction, "Use when: The task names a page."
          assert_includes instruction, "Do not use when: The task asks to rename a page."
          assert_includes instruction, "title (string, required): Title of the page."
          assert_includes instruction, "folder (string, optional): Folder name when the title is shared."
          assert_includes instruction, "Returns: The page recording id."
          refute_includes instruction, "recording_studio_agents_request_handoff"
          refute_includes instruction, "target_agent_key"
          assert_equal [], call[:custom_tools]
          arguments = call[:schema].dig("properties", "action_candidates", "items", "properties", "arguments")
          assert_equal "object", arguments["type"]
          refute arguments.key?("oneOf")
        end
      end
    end
  end

  def test_missing_required_arguments_are_filled_before_the_tool_runs
    RecordingStudioAgents.agents.register(
      key: :reviewer, version: 1, name: "Reviewer", description: "Reviews", instructions: "Review."
    )
    register_librarian(handoffs: { reviewer: 1 })
    retune_tool(:find_page, parameters: [required_title])
    seen = []
    performed = []
    generate = lambda do |**kwargs|
      seen << kwargs
      if kwargs[:request_id].to_s.include?(":arguments-")
        arguments_response({ "title" => "Getting Started" }, 21)
      elsif kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "Found Getting Started.", run_id: 22)
      else
        empty_arguments_plan(
          20,
          "Find the page titled Getting Started.",
          extra: [deliver_candidate, handoff_candidate("reviewer", 1)]
        )
      end
    end
    decide = lambda do |**|
      decision(finished: 0.1, choice_id: "1", candidate_ids: %w[1 deliver handoff_reviewer])
    end
    perform = lambda do |**kwargs|
      performed << kwargs[:arguments]
      performance(summary: "Found Getting Started.", criteria: ["done"])
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("fill-arguments")

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal [{ "title" => "Getting Started" }], performed
          fills = seen.select { |call| call[:request_id].to_s.include?(":arguments-") }
          assert_equal 1, fills.length
          fill = fills.first
          assert_equal ["title"], fill[:schema]["required"]
          assert_equal false, fill[:schema]["additionalProperties"]
          assert_equal [], fill[:custom_tools]
          assert_equal :medium, fill[:profile]
          assert_includes fill[:prompt], "Find Getting Started."
          assert_includes fill[:prompt], "Find the page titled Getting Started."
          refute_includes fill[:system_instruction], "action_candidates"
          assert_equal 2, result.run.reload.working_state_json.dig("counters", "reasoner_calls")
          assert_equal 0, result.run.working_state_json.dig("counters", "replans")
          step = result.run.agent_steps.find_by!(action_type: "arguments", status: "completed")
          assert_equal "Filled in the missing details.", step.observation_summary
          refute_includes step.observation_summary, "Getting Started"
          assert result.run.agent_steps.exists?(action_type: "deliver", status: "completed")
          refute result.run.agent_steps.exists?(action_type: "handoff")
          ids = result.run.working_state_json["candidate_index"].map { |entry| entry["id"] }
          assert_includes ids, "deliver"
          assert_includes ids, "handoff_reviewer"
          refute_includes ids, "1"
        end
      end
    end
  end

  def test_an_empty_object_skips_the_extra_call_when_nothing_is_required
    register_ai_tool(:list_pages, description: "List the pages.")
    register_librarian(tools: { find_page: 1, list_pages: 1 })
    seen = []
    performed = []
    generate = lambda do |**kwargs|
      seen << kwargs[:request_id].to_s
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "Listed the pages.", run_id: 29)
      else
        list_pages_plan(28)
      end
    end
    perform = lambda do |**kwargs|
      performed << kwargs[:arguments]
      performance(summary: "Pages: Home", criteria: ["done"])
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, ->(**) { decision(finished: 0.1, choice_id: "1", candidate_ids: ["1"]) }) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("list-pages-empty")

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal [{}], performed
          refute(seen.any? { |request_id| request_id.include?(":arguments-") })
          assert_equal 1, result.run.reload.working_state_json.dig("counters", "reasoner_calls")
        end
      end
    end
  end

  def test_arguments_with_the_wrong_type_are_filled_from_the_tool_schema
    register_librarian
    retune_tool(:find_page, parameters: [required_title])
    seen = []
    performed = []
    generate = lambda do |**kwargs|
      seen << kwargs
      if kwargs[:request_id].to_s.include?(":arguments-")
        arguments_response({ "title" => "Getting Started" }, 33)
      elsif kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "Found it.", run_id: 34)
      else
        wrong_type_plan(32)
      end
    end
    perform = lambda do |**kwargs|
      performed << kwargs[:arguments]
      performance(summary: "Found it.", criteria: ["done"])
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, ->(**) { decision(finished: 0.1, choice_id: "1", candidate_ids: ["1"]) }) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("arguments-wrong-type")

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal [{ "title" => "Getting Started" }], performed
          assert_equal(1, seen.count { |call| call[:request_id].to_s.include?(":arguments-") })
        end
      end
    end
  end

  def test_present_required_arguments_skip_the_extra_call
    register_librarian
    retune_tool(:find_page, parameters: [required_title])
    seen = []
    performed = []
    generate = lambda do |**kwargs|
      seen << kwargs[:request_id].to_s
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "Found it.", run_id: 24)
      else
        titled_plan(23)
      end
    end
    perform = lambda do |**kwargs|
      performed << kwargs[:arguments]
      performance(summary: "Found it.", criteria: ["done"])
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, ->(**) { decision(finished: 0.1, choice_id: "1", candidate_ids: ["1"]) }) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("arguments-present")

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal [{ "title" => "Getting Started" }], performed
          refute(seen.any? { |request_id| request_id.include?(":arguments-") })
        end
      end
    end
  end

  def test_arguments_that_stay_invalid_are_dropped
    register_librarian
    retune_tool(:find_page, parameters: [required_title])
    previous = RecordingStudioAgents.configuration.maximum_replans
    RecordingStudioAgents.configuration.maximum_replans = 1
    performed = 0
    generate = lambda do |**kwargs|
      if kwargs[:request_id].to_s.include?(":arguments-")
        arguments_response({}, 26)
      else
        empty_arguments_plan(25, "Find the page titled Getting Started.")
      end
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, ->(**) { decision(finished: 0.1, choice_id: "1", candidate_ids: ["1"]) }) do
        RecordingStudioAI.stub(:perform_tool, ->(**) { performed += 1 }) do
          result = run_librarian("arguments-still-empty")

          assert_instance_of RecordingStudioAgents::Results::Failed, result
          assert_equal "maximum_replans", result.failure.code
          assert_equal 0, performed
          assert result.run.agent_steps.exists?(action_type: "arguments", status: "failed")
          refute result.run.agent_steps.exists?(action_type: "tool")
        end
      end
    end
  ensure
    RecordingStudioAgents.configuration.maximum_replans = previous
  end

  def test_the_same_arguments_for_two_tools_do_not_share_a_digest
    web = RecordingStudioAgents::ActionMenu::Candidate.new(
      id: "web", type: "tool", purpose: "Search", tool_key: "web_search", tool_version: 1,
      arguments: { "query" => "Acme" }
    )
    other = RecordingStudioAgents::ActionMenu::Candidate.new(
      id: "other", type: "tool", purpose: "Search", tool_key: "x_search", tool_version: 1,
      arguments: { query: "Acme" }
    )

    refute_equal web.argument_digest, other.argument_digest
    assert_equal web.argument_digest, RecordingStudioAgents::Digests.of(
      "tool_key" => "web_search",
      "tool_version" => 1,
      "arguments" => { "query" => "Acme" }
    )
  end

  def test_an_explicit_empty_candidate_list_enters_the_runtime
    register_librarian
    generate = lambda do |**kwargs|
      if kwargs[:prompt].to_s.include?("no usable action candidates")
        plan_response(candidates: 0, extra: [deliver_candidate], run_id: 44)
      elsif kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "The real answer.", run_id: 45)
      else
        empty_candidate_plan(43)
      end
    end

    decide = ->(**) { decision(finished: 0.95, choice_id: "deliver", candidate_ids: ["deliver"]) }
    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        result = run_librarian("empty-candidates")

        assert_instance_of RecordingStudioAgents::Results::Completed, result
        assert_equal "The real answer.", result.output.text
      end
    end
  end

  def test_a_failed_answer_does_not_succeed_the_run
    register_librarian
    error = Struct.new(:message, :category, :code, :retryable?).new(
      "The model stopped.", "provider_error", "generation_failed", false
    )
    generate = lambda do |**kwargs|
      if kwargs[:request_id].to_s.end_with?(":answer")
        Struct.new(:text, :error, :run, :structured_data).new("", error, Struct.new(:id).new(46), nil)
      else
        deliver_only_plan(47)
      end
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, ->(**) { decision(finished: 0.95, choice_id: "1", candidate_ids: ["1"]) }) do
        result = run_librarian("synthesis-failed")

        assert_instance_of RecordingStudioAgents::Results::Failed, result
        assert_equal "synthesis_failed", result.failure.code
        assert_equal "failed", result.run.status
      end
    end
  end

  def test_a_stored_tool_outcome_is_kept_after_a_crash
    register_librarian
    calls = []
    generate = ->(**kwargs) { crash_generate(kwargs) }
    decide = ->(**kwargs) { crash_decide(kwargs, :first, []) }
    perform = lambda do |**kwargs|
      calls << kwargs
      raise "worker died" unless kwargs[:arguments].nil?

      performance(summary: "Stored page.", criteria: ["done"])
    end
    find_run = lambda do |request_id:|
      request_id.to_s.include?(":tool:") ? Struct.new(:id).new(9) : nil
    end

    RecordingStudioAgents::Ai.stub(:find_run, find_run) do
      RecordingStudioAI.stub(:generate, generate) do
        RecordingStudioAI.stub(:decide, decide) do
          RecordingStudioAI.stub(:perform_tool, perform) do
            first = run_librarian("stored-replay")
            second = run_librarian("stored-replay")

            assert_instance_of RecordingStudioAgents::Results::Failed, first
            assert_instance_of RecordingStudioAgents::Results::Completed, second
            assert_equal "Recovered.", second.output.text
            assert_equal "Stored page.", second.run.agent_steps.find_by!(action_type: "tool").observation_summary
            assert_equal(1, calls.count { |call| call[:arguments].nil? })
            assert_equal 0, second.run.agent_steps.where(status: "unresolved").count
            assert second.run.agent_steps.exists?(action_type: "tool", status: "completed")
          end
        end
      end
    end
  end

  def test_an_in_progress_tool_stays_unresolved
    register_librarian
    phase = :first
    calls = []
    generate = ->(**kwargs) { crash_generate(kwargs) }
    decide = ->(**kwargs) { crash_decide(kwargs, phase, []) }
    perform = lambda do |**kwargs|
      calls << kwargs[:arguments]
      if kwargs[:arguments].nil?
        raise RecordingStudioAI::Errors::ContractValidationError.new(
          "tool run is already in progress", code: "invalid_request"
        )
      end

      raise "worker died"
    end
    find_run = ->(request_id:) { request_id.to_s.include?(":tool:") ? Struct.new(:id).new(9) : nil }

    RecordingStudioAgents::Ai.stub(:find_run, find_run) do
      RecordingStudioAI.stub(:generate, generate) do
        RecordingStudioAI.stub(:decide, decide) do
          RecordingStudioAI.stub(:perform_tool, perform) do
            first = run_librarian("in-progress-tool")
            phase = :second
            second = run_librarian("in-progress-tool")

            assert_instance_of RecordingStudioAgents::Results::Failed, first
            failure_code = second.respond_to?(:failure) ? second.failure&.code : nil
            refute_equal "invalid_request", failure_code
            assert_equal 1, calls.count(nil)
            assert_equal 1, second.run.agent_steps.where(status: "unresolved").count
          end
        end
      end
    end
  end

  def test_a_spent_reasoner_budget_drops_a_candidate_with_missing_arguments
    register_librarian
    retune_tool(:find_page, parameters: [required_title])
    previous = RecordingStudioAgents.configuration.maximum_reasoner_calls
    RecordingStudioAgents.configuration.maximum_reasoner_calls = 1
    seen = []
    generate = lambda do |**kwargs|
      seen << kwargs[:request_id].to_s
      empty_arguments_plan(27, "Find the page titled Getting Started.")
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, ->(**) { decision(finished: 0.1, choice_id: "1", candidate_ids: ["1"]) }) do
        RecordingStudioAI.stub(:perform_tool, ->(**) { flunk "the tool should not run" }) do
          result = run_librarian("arguments-budget")

          assert_instance_of RecordingStudioAgents::Results::Failed, result
          assert_equal "maximum_reasoner_calls", result.failure.code
          refute(seen.any? { |request_id| request_id.include?(":arguments-") })
          refute result.run.agent_steps.exists?(action_type: "arguments")
        end
      end
    end
  ensure
    RecordingStudioAgents.configuration.maximum_reasoner_calls = previous
  end

  def test_a_deliver_only_plan_still_asks_the_controller
    register_librarian
    plans = 0
    decisions = 0
    seen = []
    generate = lambda do |**kwargs|
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "No pages about dogs.", run_id: 11)
      else
        plans += 1
        plans == 1 ? tool_only_plan(1) : deliver_only_plan(2)
      end
    end
    choice_number = 0
    decide = lambda do |**kwargs|
      decisions += 1
      criteria = kwargs[:questions].dig(:next_action, :criteria)
      if criteria.nil?
        seen << ["completion"]
        next decision(finished: 0.1, stuck: 0.05, choice_id: "1", candidate_ids: ["1"])
      end

      ids = criteria.keys.map(&:to_s)
      seen << ids
      choice_number += 1
      decision(finished: choice_number == 1 ? 0.1 : 0.95, choice_id: "1", candidate_ids: ids)
    end
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: { "pages" => [{ "title" => "Guides" }] },
        error: nil,
        run: Struct.new(:id).new(12)
      )
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("deliver-only")

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal "No pages about dogs.", result.output.text
          assert_equal 3, decisions
          assert_equal [%w[1], ["completion"], %w[1]], seen
        end
      end
    end
  end

  def test_a_page_list_does_not_invent_an_answer
    register_librarian
    seen = []
    generate = lambda do |**kwargs|
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "No pages about dogs.", run_id: 8)
      else
        tool_only_plan(1)
      end
    end
    decide = lambda do |**kwargs|
      criteria = kwargs[:questions].dig(:next_action, :criteria)
      if criteria.nil?
        seen << ["completion"]
        next decision(finished: 0.1, stuck: 0.05, choice_id: "1", candidate_ids: ["1"])
      end

      ids = criteria.keys.map(&:to_s)
      seen << ids
      decision(finished: 0.1, choice_id: "1", candidate_ids: ids)
    end
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: { "pages" => [{ "title" => "Guides" }] },
        error: nil,
        run: Struct.new(:id).new(9)
      )
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("answer-the-list")

          assert_instance_of RecordingStudioAgents::Results::Failed, result
          assert_equal "maximum_replans", result.failure.code
          assert_equal [%w[1], ["completion"], %w[1], ["completion"], %w[1], ["completion"]], seen
          refute result.run.agent_steps.exists?(candidate_id: "answer")
        end
      end
    end
  end

  def test_observations_can_finish_when_no_candidates_remain
    register_librarian
    questions = []
    generate = lambda do |**kwargs|
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "No pages about dogs.", run_id: 21)
      else
        tool_only_plan(21)
      end
    end
    decide = lambda do |**kwargs|
      questions << kwargs[:questions]
      if kwargs[:questions].key?(:next_action)
        decision(finished: 0.1, choice_id: "1", candidate_ids: ["1"])
      else
        decision(finished: 0.9, stuck: 0.1, choice_id: "1", candidate_ids: ["1"])
      end
    end
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: { "pages" => [{ "title" => "Guides" }] },
        error: nil,
        run: Struct.new(:id).new(22)
      )
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("observations-finish")

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal "No pages about dogs.", result.output.text
          assert_equal 1, result.run.agent_steps.where(action_type: "tool", status: "completed").count
          refute result.run.agent_steps.exists?(candidate_id: "answer")
          assert_equal %i[finished stuck], questions.last.keys
          assert_includes questions.last[:finished][:instructions], "current observations"
        end
      end
    end
  end

  def test_met_criteria_finish_when_the_menu_is_empty
    register_librarian
    decided = 0
    generate = lambda do |**kwargs|
      if kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "The pages were checked.", run_id: 31)
      else
        tool_only_plan(31)
      end
    end
    decide = lambda do |**|
      decided += 1
      decision(finished: 0.1, choice_id: "1", candidate_ids: ["1"])
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, ->(**) { performance(summary: "Pages: Guides", criteria: ["done"]) }) do
          result = run_librarian("criteria-empty-menu")

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal "The pages were checked.", result.output.text
          assert_equal 1, decided
        end
      end
    end
  end

  def test_a_page_list_stays_in_the_observation
    register_librarian
    calls = 0
    decide = lambda do |**|
      calls += 1
      if calls == 1
        decision(finished: 0.1, choice_id: "action_1", candidate_ids: %w[action_1 deliver])
      else
        decision(finished: 0.95, choice_id: "deliver", candidate_ids: ["deliver"])
      end
    end
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: { "pages" => [{ "title" => "Guides" }, { "title" => "People" }] },
        error: nil,
        run: Struct.new(:id).new(9)
      )
    end

    RecordingStudioAI.stub(:generate, ->(**kwargs) { listed_generate(kwargs) }) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("page-list")
          observation = result.run.agent_steps.find_by!(action_type: "tool").observation_summary

          assert_includes observation, "Guides"
          assert_includes observation, "People"
        end
      end
    end
  end

  def test_a_page_list_does_not_ask_for_another_summary
    register_librarian
    calls = []
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: { "pages" => [{ "title" => "Guides" }, { "title" => "People" }] },
        error: nil,
        run: Struct.new(:id).new(11)
      )
    end

    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      calls << kwargs
      listed_generate(kwargs)
    }) do
      RecordingStudioAI.stub(:decide, page_decisions) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("page-list-no-observe")
          observation = result.run.agent_steps.find_by!(action_type: "tool").observation_summary
          state = RecordingStudioAgents::WorkingState.load(result.run.working_state_json)

          assert_equal "Pages: Guides, People", observation
          assert_equal 0, state.counter("observation_calls")
          refute(calls.any? { |call| call[:request_id].to_s.include?(":observe-") })
        end
      end
    end
  end

  def test_a_small_record_keeps_its_fields
    register_librarian
    calls = []
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: { "author" => "Ada", "year" => 2024 },
        error: nil,
        run: Struct.new(:id).new(12)
      )
    end

    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      calls << kwargs
      listed_generate(kwargs)
    }) do
      RecordingStudioAI.stub(:decide, page_decisions) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("small-record")
          observation = result.run.agent_steps.find_by!(action_type: "tool").observation_summary

          assert_equal "author: Ada. year: 2024", observation
          refute(calls.any? { |call| call[:request_id].to_s.include?(":observe-") })
        end
      end
    end
  end

  def test_a_titled_record_keeps_its_other_fields
    register_librarian
    calls = []
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: { "title" => "Staff handbook", "author" => "Ada" },
        error: nil,
        run: Struct.new(:id).new(13)
      )
    end

    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      calls << kwargs
      listed_generate(kwargs)
    }) do
      RecordingStudioAI.stub(:decide, page_decisions) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("titled-record")
          observation = result.run.agent_steps.find_by!(action_type: "tool").observation_summary

          assert_equal "title: Staff handbook. author: Ada", observation
          refute(calls.any? { |call| call[:request_id].to_s.include?(":observe-") })
        end
      end
    end
  end

  def test_a_missing_page_keeps_the_found_flag
    register_librarian
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: { "found" => false, "title" => "time off policy" },
        error: nil,
        run: Struct.new(:id).new(41)
      )
    end

    RecordingStudioAI.stub(:generate, ->(**kwargs) { listed_generate(kwargs) }) do
      RecordingStudioAI.stub(:decide, page_decisions) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("missing-page")
          observation = result.run.agent_steps.find_by!(action_type: "tool").observation_summary

          assert_equal "found: false. title: time off policy", observation
          refute_includes observation, "Found"
        end
      end
    end
  end

  def test_a_found_page_keeps_its_path_and_recording_id
    register_librarian
    calls = []
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: {
          "found" => true,
          "title" => "Home",
          "path" => "/",
          "page_recording_id" => "fa0c47cb-d34d-4870-94cb-5ca44389ca2c"
        },
        error: nil,
        run: Struct.new(:id).new(42)
      )
    end

    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      calls << kwargs
      listed_generate(kwargs)
    }) do
      RecordingStudioAI.stub(:decide, page_decisions) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("found-page-fields")
          observation = result.run.agent_steps.find_by!(action_type: "tool").observation_summary
          state = RecordingStudioAgents::WorkingState.load(result.run.working_state_json)

          assert_equal "found: true. title: Home. path: /. page_recording_id: fa0c47cb-d34d-4870-94cb-5ca44389ca2c",
                       observation
          assert_equal 0, state.counter("observation_calls")
          refute(calls.any? { |call| call[:request_id].to_s.include?(":observe-") })
        end
      end
    end
  end

  def test_a_page_list_keeps_a_path_and_a_folder
    register_librarian
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: {
          "pages" => [
            { "title" => "Home", "path" => "/" },
            { "title" => "Getting Started", "folder" => "Studio" },
            { "title" => "People" }
          ]
        },
        error: nil,
        run: Struct.new(:id).new(43)
      )
    end

    RecordingStudioAI.stub(:generate, ->(**kwargs) { listed_generate(kwargs) }) do
      RecordingStudioAI.stub(:decide, page_decisions) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("page-list-path")
          observation = result.run.agent_steps.find_by!(action_type: "tool").observation_summary

          assert_equal "Pages: Home (/), Getting Started in Studio, People", observation
        end
      end
    end
  end

  def test_a_later_argument_fill_sees_the_stored_observation
    register_librarian(tools: { find_page: 1, retitle_page: 1 })
    register_ai_tool(
      :retitle_page,
      parameters: [
        { name: "page_recording_id", type: "string", required: true, description: "The page to retitle." },
        { name: "title", type: "string", required: true, description: "The new title." }
      ],
      read_only: false
    )
    recording_id = "fa0c47cb-d34d-4870-94cb-5ca44389ca2c"
    calls = []
    performed = []
    counter = { choices: 0 }

    RecordingStudioAI.stub(:generate, ->(**kwargs) { observation_fill_generate(kwargs, calls, recording_id) }) do
      RecordingStudioAI.stub(:decide, ->(**kwargs) { observation_fill_decide(kwargs, counter) }) do
        RecordingStudioAI.stub(:perform_tool, lambda { |**kwargs|
          observation_fill_perform(kwargs, performed, recording_id)
        }) do
          result = run_librarian("fill-from-observation")
          fill = calls.find { |call| call[:request_id].to_s.include?(":arguments-") }
          observation = result.run.agent_steps.where(action_type: "tool").order(:sequence).first.observation_summary

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          assert_equal "found: true. title: Getting Started. page_recording_id: #{recording_id}", observation
          assert_includes fill[:prompt], "RECENT OBSERVATIONS"
          assert_includes fill[:prompt], observation
          assert_includes fill[:prompt], "IMPORTANT FINDINGS"
          assert_includes fill[:prompt], "Use recording #{recording_id}."
          assert_equal recording_id, performed.last[:arguments]["page_recording_id"]
          assert_equal "Studio welcome", performed.last[:arguments]["title"]
        end
      end
    end
  end

  def test_a_long_tool_result_uses_one_cheap_summary
    register_librarian
    calls = []
    secret = "sekret-value"
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: {
          "title" => "Handbook",
          "body" => "x" * 250,
          "api_token" => secret,
          "findings" => ["The tool found the handbook."]
        },
        error: nil,
        run: Struct.new(:id).new(14)
      )
    end
    generate = lambda do |**kwargs|
      calls << kwargs
      if kwargs[:request_id].to_s.include?(":observe-")
        observation_response(
          { "summary" => "The handbook covers onboarding.", "add_findings" => ["Onboarding is documented."] },
          15
        )
      else
        listed_generate(kwargs)
      end
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, page_decisions) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("long-result")
          observation = result.run.agent_steps.find_by!(action_type: "tool").observation_summary
          state = RecordingStudioAgents::WorkingState.load(result.run.working_state_json)
          observe = calls.find { |call| call[:request_id].to_s.include?(":observe-") }
          stored = result.run.working_state_json.to_json

          assert_equal "The handbook covers onboarding.", observation
          assert_includes state.data["findings"], "Onboarding is documented."
          assert_includes state.data["findings"], "The tool found the handbook."
          assert_equal 1, state.counter("observation_calls")
          assert_equal 1, state.counter("reasoner_calls")
          assert_equal :low, observe[:profile]
          assert_equal [], observe[:custom_tools]
          assert_equal ["summary"], observe[:schema]["required"]
          refute_includes observe[:prompt], secret
          refute_includes observation, secret
          refute_includes stored, secret
        end
      end
    end
  end

  def test_a_bad_observation_keeps_the_title
    register_librarian
    perform = lambda do |**|
      Performance.new(
        status: "completed",
        result: { "title" => "Handbook", "body" => "y" * 250, "api_token" => "sekret-value" },
        error: nil,
        run: Struct.new(:id).new(16)
      )
    end
    generate = lambda do |**kwargs|
      if kwargs[:request_id].to_s.include?(":observe-")
        observation_response({ "summary" => "sekret-value leaked" }, 17)
      else
        listed_generate(kwargs)
      end
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, page_decisions) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("bad-observation")
          observation = result.run.agent_steps.find_by!(action_type: "tool").observation_summary
          state = RecordingStudioAgents::WorkingState.load(result.run.working_state_json)

          assert_equal "leaked", observation
          assert_equal 1, state.counter("observation_calls")
          assert_equal 1, state.counter("reasoner_calls")
          refute_includes result.run.working_state_json.to_json, "sekret-value"
        end
      end
    end
  end

  def test_a_spent_observation_budget_keeps_the_title
    register_librarian
    calls = []
    previous = RecordingStudioAgents.configuration.maximum_observation_calls
    RecordingStudioAgents.configuration.maximum_observation_calls = 1
    perform = lambda do |**kwargs|
      title = kwargs[:arguments]["note"] == "note-1" ? "First" : "Second"
      Performance.new(
        status: "completed",
        result: { "title" => title, "body" => "z" * 250 },
        error: nil,
        run: Struct.new(:id).new(18)
      )
    end
    generate = lambda do |**kwargs|
      calls << kwargs
      if kwargs[:request_id].to_s.include?(":observe-")
        observation_response({ "summary" => "Kept the first note." }, 19)
      elsif kwargs[:request_id].to_s.end_with?(":answer")
        generation_response(text: "Both notes are in.", run_id: 20)
      else
        plan_response(candidates: 2, run_id: 21)
      end
    end
    choices = 0
    decide = lambda do |**|
      choices += 1
      case choices
      when 1 then decision(finished: 0.1, choice_id: "action_1", candidate_ids: %w[action_1 action_2 deliver])
      when 2 then decision(finished: 0.1, choice_id: "action_2", candidate_ids: %w[action_2 deliver])
      else decision(finished: 0.95, choice_id: "deliver", candidate_ids: ["deliver"])
      end
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("observation-budget")
          steps = result.run.agent_steps.where(action_type: "tool").order(:sequence)
          state = RecordingStudioAgents::WorkingState.load(result.run.working_state_json)

          assert_equal ["Kept the first note.", "Found Second."], steps.map(&:observation_summary)
          assert_equal(1, calls.count { |call| call[:request_id].to_s.include?(":observe-") })
          assert_equal 1, state.counter("observation_calls")
          assert_equal 1, state.counter("reasoner_calls")
        end
      end
    end
  ensure
    RecordingStudioAgents.configuration.maximum_observation_calls = previous
  end

  def test_a_missing_tool_runner_fails_the_started_step
    register_librarian
    message = "Tool steps need RecordingStudioAI.perform_tool. This Recording Studio AI gem does not provide it."
    decide = ->(**) { decision(finished: 0.1, choice_id: "action_1", candidate_ids: %w[action_1 deliver]) }
    perform = ->(**) { raise RecordingStudioAgents::ConfigurationError, message }

    RecordingStudioAI.stub(:generate, ->(**kwargs) { listed_generate(kwargs) }) do
      RecordingStudioAI.stub(:decide, decide) do
        RecordingStudioAI.stub(:perform_tool, perform) do
          result = run_librarian("missing-tool")
          step = result.run.agent_steps.find_by!(action_type: "tool")

          assert_instance_of RecordingStudioAgents::Results::Failed, result
          assert_equal "failed", result.run.status
          assert_equal "failed", step.status
          assert_equal message, step.observation_summary
          assert_equal "tool_unavailable", result.failure.code
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

    answered = decision_answers(finished: 0.8, stuck: 0.1, choice_id: "search", candidate_ids: ["search"])
    completion = RecordingStudioAgents::Controller.interpret_completion(answered, configuration: configuration)
    assert_predicate completion, :finish?
    assert_nil completion.candidate_id

    stuck_answer = decision_answers(finished: 0.9, stuck: 0.7, choice_id: "search", candidate_ids: ["search"])
    withheld = RecordingStudioAgents::Controller.interpret_completion(stuck_answer, configuration: configuration)
    assert_predicate withheld, :reason?
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

  def test_a_compact_delta_replaces_lists
    state = RecordingStudioAgents::WorkingState.load({
                                                       "goal" => "Stay",
                                                       "findings" => ["old finding"],
                                                       "completed_work" => ["old work"],
                                                       "failed_work" => ["old failure"],
                                                       "recent_observations" => [
                                                         { "sequence" => 1, "summary" => "old note" }
                                                       ]
                                                     })
    updated, = RecordingStudioAgents::StateDelta.apply(state, {
                                                         "replace_findings" => ["new finding"],
                                                         "replace_completed" => ["new work"],
                                                         "replace_failed" => ["new failure"],
                                                         "replace_observations" => ["new note"]
                                                       })

    assert_equal ["new finding"], updated.data["findings"]
    assert_equal ["new work"], updated.data["completed_work"]
    assert_equal ["new failure"], updated.data["failed_work"]
    assert_equal(["new note"], updated.data["recent_observations"].map { |item| item["summary"] })
  end

  def test_a_stored_observation_is_rewritten_before_the_hard_trim
    register_librarian
    previous = RecordingStudioAgents.configuration.soft_working_state_bytes
    RecordingStudioAgents.configuration.soft_working_state_bytes = 1_000
    calls = []
    decided = []
    long = "S" * 400
    generate = lambda do |**kwargs|
      calls << kwargs
      request_id = kwargs[:request_id].to_s
      if request_id.end_with?(":answer")
        generation_response(text: "Done.", run_id: 30)
      elsif request_id.include?(":compact-")
        observation_response(
          {
            "replace_observations" => ["Kept the latest page."],
            "replace_findings" => ["The page is the one that matters."]
          },
          31
        )
      else
        plan_response(candidates: 1, run_id: 32)
      end
    end

    decider = page_decisions
    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, lambda { |**kwargs|
        decided << kwargs
        decider.call(**kwargs)
      }) do
        RecordingStudioAI.stub(:perform_tool, ->(**) { performance(summary: long, finding: long) }) do
          result = run_librarian("soft-compact")
          state = RecordingStudioAgents::WorkingState.load(result.run.working_state_json)
          compact = calls.find { |call| call[:request_id].to_s.include?(":compact-") }

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          summaries = state.data["recent_observations"].map { |item| item["summary"] }
          assert_equal ["Kept the latest page."], summaries
          assert_equal ["The page is the one that matters."], state.data["findings"]
          refute_includes state.to_json, long
          assert_equal 1, state.counter("compactions")
          assert_equal 1, state.counter("reasoner_calls")
          assert_equal :low, compact[:profile]
          assert_equal [], compact[:custom_tools]
          assert_includes decided.last[:state], "Kept the latest page."
          refute_includes decided.last[:state], long
        end
      end
    end
  ensure
    RecordingStudioAgents.configuration.soft_working_state_bytes = previous
  end

  def test_a_bad_compact_keeps_the_observation
    register_librarian
    previous = RecordingStudioAgents.configuration.soft_working_state_bytes
    RecordingStudioAgents.configuration.soft_working_state_bytes = 1_000
    calls = []
    long = "T" * 400
    generate = lambda do |**kwargs|
      calls << kwargs
      request_id = kwargs[:request_id].to_s
      if request_id.end_with?(":answer")
        generation_response(text: "Done.", run_id: 33)
      elsif request_id.include?(":compact-")
        observation_response({ "erase_goal" => true }, 34)
      else
        plan_response(candidates: 1, run_id: 35)
      end
    end

    RecordingStudioAI.stub(:generate, generate) do
      RecordingStudioAI.stub(:decide, page_decisions) do
        RecordingStudioAI.stub(:perform_tool, ->(**) { performance(summary: long) }) do
          result = run_librarian("bad-compact")
          state = RecordingStudioAgents::WorkingState.load(result.run.working_state_json)

          assert_instance_of RecordingStudioAgents::Results::Completed, result
          compact_calls = calls.count { |call| call[:request_id].to_s.include?(":compact-") }

          assert_includes state.to_json, long
          assert_operator state.counter("compactions"), :>=, 1
          assert_operator state.counter("compactions"), :<=, 3
          assert_equal 1, state.counter("reasoner_calls")
          assert_operator compact_calls, :>=, 1
          assert_operator compact_calls, :<=, 3
        end
      end
    end
  ensure
    RecordingStudioAgents.configuration.soft_working_state_bytes = previous
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

  def test_a_tool_code_or_dotted_key_is_not_admitted
    register_librarian
    program = RecordingStudioAgents::Programs::Compiler.compile(
      definition: RecordingStudioAgents.agents.fetch(:librarian, version: 1)
    )
    menu = RecordingStudioAgents::ActionMenu.admit(
      [
        candidate("list", "pages").merge(
          "type" => "tool_code",
          "tool_key" => "page_lookup.find_page"
        ),
        candidate("dotted", "pages").merge("tool_key" => "page_lookup.find_page")
      ],
      program: program,
      refused_digests: []
    )

    assert_nil menu.fetch("list")
    assert_nil menu.fetch("dotted")
    assert_empty menu.actionable
  end

  private

  def observation_fill_generate(kwargs, calls, recording_id)
    calls << kwargs
    request_id = kwargs[:request_id].to_s
    if request_id.include?(":arguments-")
      return arguments_response({ "page_recording_id" => recording_id, "title" => "Studio welcome" }, 61)
    end
    return rename_next_plan if request_id.include?(":next-")
    return generation_response(text: "The page is ready to rename.", run_id: 63) if request_id.end_with?(":answer")

    titled_plan(60)
  end

  def rename_next_plan
    response = tool_plan(62, "Rename the page.", "retitle_page", {})
    response.structured_data["current_objective"] = "Rename the page"
    response.structured_data["action_candidates"][0]["id"] = "rename"
    response
  end

  def observation_fill_decide(kwargs, counter)
    counter[:choices] += 1
    return menu_choice(kwargs) if kwargs[:questions].key?(:next_action)

    finished = counter[:choices] > 2 ? 0.95 : 0.2
    decision(finished: finished, stuck: 0.1, choice_id: "deliver", candidate_ids: ["deliver"])
  end

  def menu_choice(kwargs)
    criteria = kwargs[:questions][:next_action][:criteria]
    decision(finished: 0.1, choice_id: criteria.keys.first, candidate_ids: criteria.keys)
  end

  def observation_fill_perform(kwargs, performed, recording_id)
    performed << kwargs
    return retitle_performance if kwargs[:tool][:key].to_s == "retitle_page"

    found_page_performance(recording_id)
  end

  def retitle_performance
    Performance.new(status: "completed", result: { "title" => "Studio welcome" }, error: nil,
                    run: Struct.new(:id).new(65))
  end

  def found_page_performance(recording_id)
    Performance.new(
      status: "completed",
      result: {
        "found" => true,
        "title" => "Getting Started",
        "page_recording_id" => recording_id,
        "findings" => ["Use recording #{recording_id}."]
      },
      error: nil,
      run: Struct.new(:id).new(64)
    )
  end

  def run_librarian(idempotency_key)
    RecordingStudioAgents.agent(:librarian, version: 1).run(
      task: task_input,
      root_recording: root,
      initiator: actor,
      execution_source: :job,
      idempotency_key: idempotency_key
    )
  end

  def required_title
    { name: "title", type: "string", required: true, description: "Title of the page." }
  end

  def empty_candidate_plan(run_id)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: "Premature.",
      structured_data: {
        "plan" => ["Look"],
        "success_criteria" => [{ "id" => "done", "text" => "Found" }],
        "current_objective" => "Look",
        "action_candidates" => []
      },
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def empty_arguments_plan(run_id, purpose, extra: [])
    tool_plan(run_id, purpose, "find_page", {}, extra: extra)
  end

  def list_pages_plan(run_id)
    tool_plan(run_id, "List the pages.", "list_pages", {})
  end

  def wrong_type_plan(run_id)
    tool_plan(run_id, "Find the page titled Getting Started.", "find_page", { "title" => 1 })
  end

  def deliver_candidate
    { "id" => "deliver", "type" => "deliver", "purpose" => "Write the answer" }
  end

  def tool_plan(run_id, purpose, tool_key, arguments, extra: [])
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: {
        "plan" => ["Find the page"],
        "success_criteria" => [{ "id" => "done", "text" => "The page was found" }],
        "current_objective" => "Find the page",
        "action_candidates" => [
          {
            "id" => "1",
            "type" => "tool",
            "purpose" => purpose,
            "tool_key" => tool_key,
            "tool_version" => 1,
            "arguments" => arguments
          },
          *extra
        ]
      },
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def titled_plan(run_id)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: {
        "plan" => ["Find the page"],
        "success_criteria" => [{ "id" => "done", "text" => "The page was found" }],
        "current_objective" => "Find the page",
        "action_candidates" => [
          {
            "id" => "1",
            "type" => "tool",
            "purpose" => "Find the page titled Getting Started.",
            "tool_key" => "find_page",
            "tool_version" => 1,
            "arguments" => { "title" => "Getting Started" }
          }
        ]
      },
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def page_decisions
    calls = 0
    lambda do |**|
      calls += 1
      if calls == 1
        decision(finished: 0.1, choice_id: "action_1", candidate_ids: %w[action_1 deliver])
      else
        decision(finished: 0.95, choice_id: "deliver", candidate_ids: ["deliver"])
      end
    end
  end

  def observation_response(data, run_id)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: data,
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def arguments_response(arguments, run_id)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: arguments,
      run: Struct.new(:id, :status).new(run_id, "completed")
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

  def deliver_only_plan(run_id)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: {
        "plan" => ["Answer"],
        "success_criteria" => [{ "id" => "done", "text" => "The pages were checked" }],
        "current_objective" => "Answer",
        "action_candidates" => [
          { "id" => "1", "type" => "deliver", "purpose" => "Answer the question" }
        ]
      },
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def tool_only_plan(run_id)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: {
        "plan" => ["List the pages"],
        "success_criteria" => [{ "id" => "done", "text" => "The pages were checked" }],
        "current_objective" => "List the pages",
        "action_candidates" => [
          {
            "id" => "1",
            "type" => "tool",
            "purpose" => "List pages",
            "tool_key" => "find_page",
            "tool_version" => 1,
            "arguments" => { "title" => "Dogs" }
          }
        ]
      },
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def rejected_plan(run_id)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: {
        "plan" => ["Look"],
        "success_criteria" => [{ "id" => "done", "text" => "Found" }],
        "current_objective" => "Look",
        "action_candidates" => [
          candidate("bad", "missing").merge("tool_key" => "lookup_invoice")
        ]
      },
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def listed_generate(kwargs)
    if kwargs[:request_id].to_s.end_with?(":answer")
      generation_response(text: "No matching pages.", run_id: 3)
    else
      plan_response(candidates: 1, run_id: 2)
    end
  end

  def chain_generate(kwargs, generated)
    generated << kwargs
    request_id = kwargs[:request_id].to_s
    if request_id.end_with?(":answer")
      generation_response(text: "The page is ready.", run_id: 50)
    elsif request_id.include?(":next-")
      page = kwargs[:prompt].scan(/Page \d+/).last || "missing"
      next_response(page, 51)
    else
      chain_plan(52)
    end
  end

  def chain_decide(kwargs, decided, counts)
    decided << kwargs
    if kwargs[:questions].key?(:next_action)
      criteria = kwargs[:questions][:next_action][:criteria]
      choice_id = criteria.keys.first
      decision(finished: 0.1, choice_id: choice_id, candidate_ids: criteria.keys)
    elsif counts[:tools] >= 20
      decision(finished: 0.95, stuck: 0.1, choice_id: "deliver", candidate_ids: ["deliver"])
    else
      decision(finished: 0.1, stuck: 0.05, choice_id: "deliver", candidate_ids: ["deliver"])
    end
  end

  def chain_perform(kwargs, performed, counts)
    performed << kwargs
    counts[:tools] += 1
    Performance.new(
      status: "completed",
      result: {
        "title" => "Page #{counts[:tools]}",
        "findings" => ["Opened Page #{counts[:tools]}"],
        "api_token" => "SECRET-ARGUMENT"
      },
      error: nil,
      run: Struct.new(:id).new(500)
    )
  end

  def chain_plan(run_id)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: {
        "plan" => ["Open the next page"],
        "success_criteria" => [{ "id" => "done", "text" => "Twenty pages were opened" }],
        "current_objective" => "Open the next page",
        "action_candidates" => [
          candidate("action_1", "start").merge("purpose" => "Open the first page")
        ]
      },
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def next_response(page, run_id)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_librarian",
      text: nil,
      structured_data: {
        "current_objective" => "Open #{page}",
        "action_candidates" => [
          {
            "id" => "next",
            "type" => "tool",
            "purpose" => "Open #{page}",
            "tool_key" => "find_page",
            "tool_version" => 1,
            "arguments" => { "title" => page }
          }
        ]
      },
      run: Struct.new(:id, :status).new(run_id, "completed")
    )
  end

  def assert_bounded_chain(result, generated, decided, performed)
    state = RecordingStudioAgents::WorkingState.load(result.run.working_state_json)
    stored = result.run.working_state_json.to_json + result.run.agent_steps.map(&:attributes).to_json

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_equal "The page is ready.", result.output.text
    assert_equal 20, result.run.agent_steps.where(action_type: "tool", status: "completed").count
    assert_equal({ "note" => "start" }, performed[0][:arguments])
    assert_equal "Page 1", performed[1][:arguments]["title"]
    assert_equal "Page 2", performed[2][:arguments]["title"]
    assert_equal "Page 19", performed[19][:arguments]["title"]
    assert_equal ["Open the next page"], state.data["plan"]
    assert_equal 0, state.counter("replans")
    assert_equal 20, state.counter("reasoner_calls")
    assert_equal(19, generated.count { |call| call[:request_id].to_s.include?(":next-") })
    refute(generated.any? { |call| call[:request_id].to_s.include?(":arguments-") })
    refute(generated.any? { |call| call[:request_id].to_s.include?(":observe-") })
    assert_equal [], generated.first[:custom_tools]
    refute_includes decided.last[:state], "Found Page 1."
    assert_includes decided.last[:state], "Found Page 20."
    assert_operator decided.last[:state].bytesize, :<, 8_000
    assert_operator widest_state(decided), :<, decided.first[:state].bytesize + 4_000
    refute_includes answer_call(generated)[:prompt], "Found Page 1."
    refute_includes stored, "SECRET-ARGUMENT"
    assert_equal (1..result.run.agent_steps.maximum(:sequence)).to_a, ordered_sequences(result)
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
    RecordingStudioAgents::Digests.of(
      "tool_key" => "find_page",
      "tool_version" => 1,
      "arguments" => { "note" => note }
    )
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
