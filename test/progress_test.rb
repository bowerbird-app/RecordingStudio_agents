# frozen_string_literal: true

require "test_helper"
require "securerandom"

class ProgressTest < PersistenceTestCase
  FakeInvocation = Struct.new(
    :tool_key,
    :tool_name_snapshot,
    :status,
    :created_at,
    :id,
    keyword_init: true
  )
  FakeAiRun = Struct.new(:id, :custom_tool_invocations, keyword_init: true)

  def test_knowledge_tool_snapshot_and_done
    run = create_run(status: "succeeded")
    note_knowledge!(run)
    steps = with_ai_run(invocations: [
                          FakeInvocation.new(
                            tool_key: "find_page",
                            tool_name_snapshot: "Find page",
                            status: "completed",
                            created_at: Time.current,
                            id: 1
                          )
                        ]) { RecordingStudioAgents::Progress.for(run) }

    assert_equal([
                   [:knowledge, "Checked this workspace", :done, "Done", :success],
                   [:tool, "Find page", :done, "Done", :success],
                   [:finished, "Done", :done, "Done", :success]
                 ], steps.map { |step| [step.kind, step.label, step.status, step.badge, step.badge_style] })
    refute_includes RecordingStudioAgents::AgentRun.column_names, "output_text"
    refute_includes run.attributes.keys, "output_text"
  end

  def test_humanizes_tool_key_when_snapshot_is_blank
    run = create_run(status: "succeeded")
    steps = with_ai_run(invocations: [
                          FakeInvocation.new(
                            tool_key: "find_page",
                            tool_name_snapshot: nil,
                            status: "completed",
                            created_at: Time.current,
                            id: 2
                          )
                        ]) { RecordingStudioAgents::Progress.for(run) }

    assert_includes steps.map(&:label), "Find page"
    refute_includes steps.map(&:label), "find_page"
  end

  def test_omits_unused_optional_skill_tools
    run = create_run(status: "succeeded")
    labels = with_ai_run(invocations: [
                           FakeInvocation.new(
                             tool_key: "find_page",
                             tool_name_snapshot: "Find page",
                             status: "completed",
                             created_at: Time.current,
                             id: 3
                           )
                         ]) { RecordingStudioAgents::Progress.for(run).map(&:label) }

    refute_includes labels, "Lookup invoice"
    refute_includes labels, "lookup_invoice"
    refute_includes labels, "Retitle page"
  end

  def test_skips_internal_handoff_tool_and_uses_run_status
    run = create_run(status: "handoff_requested")
    labels = with_ai_run(invocations: [
                           FakeInvocation.new(
                             tool_key: RecordingStudioAgents::Handoffs::INTERNAL_TOOL_KEY.to_s,
                             tool_name_snapshot: "Request handoff",
                             status: "completed",
                             created_at: Time.current,
                             id: 4
                           )
                         ]) { RecordingStudioAgents::Progress.for(run).map(&:label) }

    refute_includes labels, "Request handoff"
    refute_includes labels, RecordingStudioAgents::Handoffs::INTERNAL_TOOL_KEY.to_s
    assert_includes labels, "Asked for a reviewer"
  end

  def test_waiting_tool_does_not_duplicate_confirmation_step
    run = create_run(status: "awaiting_confirmation")
    steps = with_ai_run(invocations: [
                          FakeInvocation.new(
                            tool_key: "retitle_page",
                            tool_name_snapshot: "Retitle page",
                            status: "awaiting_confirmation",
                            created_at: Time.current,
                            id: 5
                          )
                        ]) { RecordingStudioAgents::Progress.for(run) }

    waiting = steps.select { |step| step.status == :waiting }
    assert_equal 1, waiting.length
    assert_equal "Retitle page", waiting.first.label
    refute_includes steps.map(&:label), "Waiting on a yes"
  end

  def test_waiting_label_comes_from_run_when_no_tool_is_waiting
    run = create_run(status: "awaiting_confirmation")
    labels = with_ai_run(invocations: []) { RecordingStudioAgents::Progress.for(run).map(&:label) }

    assert_equal ["Waiting on a yes"], labels
  end

  def test_cancelled_run_uses_failed_copy
    run = create_run(status: "cancelled")
    steps = with_ai_run(invocations: []) { RecordingStudioAgents::Progress.for(run) }

    assert_equal ["Did not finish"], steps.map(&:label)
    assert_equal :failed, steps.last.status
  end

  def test_failed_run_without_ai_tools
    run = create_run(status: "failed")
    note_knowledge!(run)
    steps = with_ai_run(invocations: []) { RecordingStudioAgents::Progress.for(run) }

    assert_equal ["Checked this workspace", "Did not finish"], steps.map(&:label)
    assert_equal :failed, steps.last.status
    assert_equal "Failed", steps.last.badge
  end

  def test_running_with_no_tools_shows_on_it
    run = create_run(status: "running")
    labels = with_ai_run(invocations: []) { RecordingStudioAgents::Progress.for(run).map(&:label) }

    assert_equal ["On it"], labels
  end

  def test_running_with_tools_does_not_add_on_it
    run = create_run(status: "running")
    labels = with_ai_run(invocations: [
                           FakeInvocation.new(
                             tool_key: "find_page",
                             tool_name_snapshot: "Find page",
                             status: "running",
                             created_at: Time.current,
                             id: 6
                           )
                         ]) { RecordingStudioAgents::Progress.for(run).map(&:label) }

    assert_equal ["Find page"], labels
    refute_includes labels, "On it"
  end

  def test_missing_ai_run_still_shows_knowledge_and_done
    run = create_run(status: "succeeded")
    note_knowledge!(run)
    RecordingStudioAgents::Ai.stub(:find_run, nil) do
      steps = RecordingStudioAgents::Progress.for(run)
      assert_equal ["Checked this workspace", "Done"], steps.map(&:label)
    end
  end

  def test_agent_run_progress_helper
    run = create_run(status: "succeeded")
    RecordingStudioAgents::Ai.stub(:find_run, nil) do
      assert_equal RecordingStudioAgents::Progress.for(run).map(&:label), run.progress.map(&:label)
    end
  end

  private

  def create_run(status:)
    task = RecordingStudioAgents::Task.create!(
      root_recording_id: root.id,
      task_key: "progress:#{SecureRandom.hex(4)}",
      goal: "Find Getting Started.",
      context_json: {},
      input_digest: "progress"
    )
    RecordingStudioAgents::AgentRun.create!(
      task: task,
      root_recording_id: root.id,
      agent_key: "librarian",
      agent_version: 1,
      program_digest: "progress",
      idempotency_key: "progress:#{SecureRandom.uuid}",
      status: status,
      initiator_type: "User",
      initiator_id: "1",
      initiator_kind: "user",
      execution_source: "web"
    )
  end

  def note_knowledge!(run)
    RecordingStudioAgents::Persistence::RunLedger.new.append_activity!(
      run,
      "knowledge_loaded",
      { "entry_count" => 1 }
    )
  end

  def with_ai_run(invocations:, &)
    fake = FakeAiRun.new(id: 99, custom_tool_invocations: invocations)
    RecordingStudioAgents::Ai.stub(:find_run, fake, &)
  end
end
