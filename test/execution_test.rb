# frozen_string_literal: true

require "test_helper"

class ExecutionTest < PersistenceTestCase
  def test_run_completes_through_stubbed_generate
    register_librarian
    result = nil
    RecordingStudioAI.stub(:generate, generation_response) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :web,
        idempotency_key: "web-1"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_equal "succeeded", result.run.status
    assert_equal 41, result.run.recording_studio_ai_run_id
    assert result.run.output_digest.present?
    refute_includes RecordingStudioAgents::AgentRun.column_names, "output_text"
    refute_includes RecordingStudioAgents::AgentRun.column_names, "output_data"
    assert_nil result.run.try(:output_text)
  end

  def test_auth_denial_does_not_create_a_run
    register_librarian
    RecordingStudioAI.configuration.authorization_handler = ->(**) { false }

    error = assert_raises(RecordingStudioAI::Errors::ContractValidationError) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :web,
        idempotency_key: "denied-1"
      )
    end
    assert_equal "authorization", error.code
    assert_equal 0, RecordingStudioAgents::AgentRun.count
    assert_equal 0, RecordingStudioAgents::Task.count
  end

  def test_blocked_when_confirmation_is_pending
    register_librarian
    error = RecordingStudioAI::Contracts::NormalizedError.new(
      category: "custom_tool_confirmation_required",
      code: "custom_tool_confirmation_pending",
      message: "Custom tool confirmation is pending."
    )
    result = nil
    RecordingStudioAI.stub(:generate, generation_response(error: error, run_id: 8)) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :web,
        idempotency_key: "confirm-1"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Blocked, result
    assert_equal "awaiting_confirmation", result.run.status
  end

  def test_failed_generation_stores_error_class_not_output
    register_librarian
    error = RecordingStudioAI::Contracts::NormalizedError.new(
      category: "provider_unavailable",
      code: "timeout",
      message: "Provider timed out",
      retryable: true
    )
    result = nil
    RecordingStudioAI.stub(:generate, generation_response(error: error, run_id: 9)) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "fail-1"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Failed, result
    assert_equal "failed", result.run.status
    assert_equal "timeout", result.run.failure_code
    assert_nil result.run.output_digest
    refute_includes result.run.attributes.keys, "output_text"
  end

  def test_generate_uses_composed_system_and_adopts_via_request_id
    register_librarian
    captured = nil
    result = nil
    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      captured = kwargs
      generation_response
    }) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "compose-1"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_equal "recording-studio-agents:#{result.run.id}", captured[:request_id]
    assert_equal result.run.id, captured[:metadata]["agent_run_id"]
    assert captured[:metadata]["lease_token"].present?
    assert_match(/Find the named page/, captured[:system_instruction])
    assert_equal "Find Getting Started.", captured[:prompt]
    assert_equal "agent_librarian", captured[:purpose]
    assert_equal [{ key: :find_page, version: 1 }], captured[:custom_tools]
  end

  def test_blocked_resume_calls_generate_again
    register_librarian
    error = RecordingStudioAI::Contracts::NormalizedError.new(
      category: "custom_tool_confirmation_required",
      code: "custom_tool_confirmation_pending",
      message: "Custom tool confirmation is pending."
    )
    RecordingStudioAI.stub(:generate, generation_response(error: error, run_id: 8)) do
      first = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :web,
        idempotency_key: "confirm-resume"
      )
      assert_instance_of RecordingStudioAgents::Results::Blocked, first
    end

    generate_calls = 0
    result = nil
    RecordingStudioAI.stub(:generate, lambda { |**|
      generate_calls += 1
      generation_response(run_id: 8)
    }) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :web,
        idempotency_key: "confirm-resume"
      )
    end

    assert_equal 1, generate_calls
    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_equal "succeeded", result.run.status
  end

  def test_failed_retry_with_same_job_id_runs_again
    register_librarian
    error = RecordingStudioAI::Contracts::NormalizedError.new(
      category: "provider_unavailable",
      code: "timeout",
      message: "Provider timed out",
      retryable: true
    )
    RecordingStudioAI.stub(:generate, generation_response(error: error, run_id: 9)) do
      first = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-retry"
      )
      assert_instance_of RecordingStudioAgents::Results::Failed, first
    end

    result = nil
    RecordingStudioAI.stub(:generate, generation_response(run_id: 10)) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "job-retry"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_equal "succeeded", result.run.status
    assert_equal 10, result.run.recording_studio_ai_run_id
  end

  def test_confirmation_pending_exception_blocks
    register_librarian
    result = nil
    RecordingStudioAI.stub(:generate, lambda { |**|
      raise RecordingStudioAI::Errors::ContractValidationError.new(
        "Custom tool confirmation is pending.",
        code: "custom_tool_confirmation_pending"
      )
    }) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :web,
        idempotency_key: "confirm-raise"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Blocked, result
    assert_equal "awaiting_confirmation", result.run.status
  end

  def test_adopt_completed_ai_run_skips_generate
    register_librarian
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "adopt-1"
      )
    end
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "adopt-1")
    run.update!(
      status: "running",
      lease_token: nil,
      lease_expires_at: 1.hour.ago,
      completed_at: nil,
      output_digest: nil
    )

    generate_called = false
    result = nil
    calls = 0
    finder = lambda { |**|
      calls += 1
      calls == 1 ? nil : Struct.new(:id, :status).new(41, "completed")
    }
    RecordingStudioAgents::Ai.stub(:find_run, finder) do
      RecordingStudioAI.stub(:generate, lambda { |**|
        generate_called = true
        generation_response
      }) do
        result = RecordingStudioAgents.agent(:librarian, version: 1).run(
          task: task_input,
          root_recording: root,
          initiator: actor,
          execution_source: :job,
          idempotency_key: "adopt-1"
        )
      end
    end

    refute generate_called
    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_equal "succeeded", result.run.status
  end

  def test_in_progress_awaiting_confirmation_returns_blocked
    register_librarian
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :web,
        idempotency_key: "blocked-open"
      )
    end
    run = RecordingStudioAgents::AgentRun.find_by!(idempotency_key: "blocked-open")
    run.update!(status: "awaiting_confirmation", lease_token: "held", lease_expires_at: 5.minutes.from_now)

    opening = RecordingStudioAgents::Persistence::Opening.new(
      kind: :in_progress,
      task: run.task,
      run: run
    )
    program = RecordingStudioAgents::Programs::Compiler.compile(
      definition: RecordingStudioAgents.agents.fetch(:librarian, version: 1)
    )
    request = RecordingStudioAgents::Execution::Request.parse(
      task: task_input,
      root_recording: root,
      initiator: actor,
      execution_source: :web,
      idempotency_key: "blocked-open"
    )
    ledger = Object.new
    ledger.define_singleton_method(:open!) { |**| opening }

    result = RecordingStudioAgents::Execution::Engine.new(program: program, ledger: ledger).call(request: request)
    assert_instance_of RecordingStudioAgents::Results::Blocked, result
  end

  def test_internal_error_marks_run_failed
    register_librarian
    result = nil
    RecordingStudioAI.stub(:generate, ->(**) { raise "boom" }) do
      result = RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "boom-1"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Failed, result
    assert_equal "failed", result.run.status
    assert_equal "RuntimeError", result.run.failure_code
    assert result.failure.retryable?
  end

  def test_blank_idempotency_key_is_rejected_before_ledger
    register_librarian
    assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: nil
      )
    end
    assert_equal 0, RecordingStudioAgents::AgentRun.count
  end

  def test_invalid_execution_source_is_rejected
    register_librarian
    error = assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents.agent(:librarian, version: 1).run(
        task: task_input,
        root_recording: root,
        initiator: actor,
        execution_source: :sidekiq,
        idempotency_key: "bad-source"
      )
    end
    assert_match(/execution_source/, error.message)
  end

  def test_default_support_run_omits_optional_skill_text
    register_support_clerk
    captured = nil
    result = nil
    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      captured = kwargs
      generation_response
    }) do
      result = RecordingStudioAgents.agent(:support_clerk, version: 1).run(
        task: task_input(key: "ticket-1", goal: "Help with this ticket."),
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "support-default"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_match(/Keep a steady voice/, captured[:system_instruction])
    refute_match(/refund window/, captured[:system_instruction])
    refute_match(/reset link/, captured[:system_instruction])
    refute_includes captured[:custom_tools], { key: :lookup_invoice, version: 1 }
    assert_equal [], result.run.selected_skills_json
    assert_nil result.run.skill_pack_key
  end

  def test_pack_run_loads_pack_skills_and_tools
    register_support_clerk
    captured = nil
    result = nil
    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      captured = kwargs
      generation_response
    }) do
      result = RecordingStudioAgents.agent(:support_clerk, version: 1).run(
        task: task_input(key: "ticket-1", goal: "Help with this ticket."),
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "support-billing",
        pack: :billing_tickets
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_match(/refund window/, captured[:system_instruction])
    refute_match(/reset link/, captured[:system_instruction])
    assert_includes captured[:custom_tools], { key: :lookup_invoice, version: 1 }
    assert_equal [{ "key" => "billing_help", "version" => 1 }], result.run.selected_skills_json
    assert_equal "billing_tickets", result.run.skill_pack_key
    assert_equal 1, result.run.skill_pack_version
    composed = result.run.activities.find { |activity| activity.kind == "program_composed" }
    assert_equal "billing_help:1", composed.data["selected_skill_keys"]
  end

  def test_same_key_with_different_pack_is_an_idempotency_conflict
    register_support_clerk
    RecordingStudioAI.stub(:generate, generation_response) do
      RecordingStudioAgents.agent(:support_clerk, version: 1).run(
        task: task_input(key: "ticket-1", goal: "Help with this ticket."),
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "support-same-key"
      )
    end

    error = assert_raises(RecordingStudioAgents::IdempotencyConflict) do
      RecordingStudioAgents.agent(:support_clerk, version: 1).run(
        task: task_input(key: "ticket-1", goal: "Help with this ticket."),
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "support-same-key",
        pack: :billing_tickets
      )
    end
    assert_match(/different program/, error.message)
  end

  def test_hash_pack_selects_the_listed_version
    register_support_clerk
    result = nil
    RecordingStudioAI.stub(:generate, generation_response) do
      result = RecordingStudioAgents.agent(:support_clerk, version: 1).run(
        task: task_input(key: "ticket-2", goal: "Help with this ticket."),
        root_recording: root,
        initiator: actor,
        execution_source: :job,
        idempotency_key: "support-hash-pack",
        pack: { billing_tickets: 1 }
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_equal "billing_tickets", result.run.skill_pack_key
  end
end
