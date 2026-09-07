# frozen_string_literal: true

class AgentsController < ApplicationController
  def create
    root = current_root_recording
    unless root
      redirect_to root_path, alert: "Pick a workspace first."
      return
    end

    page = Page.find_by(title: "Getting Started")
    page_recording = page && RecordingStudio::Recording.find_by(recordable: page, root_recording: root)

    task = RecordingStudioAgents::TaskInput.new(
      key: "find_page:#{root.id}:#{SecureRandom.uuid}",
      goal: "Find the Getting Started page.",
      context: { "page_recording_id" => page_recording&.id }
    )

    result = with_generate_stub do
      RecordingStudioAgents.agent(:page_librarian, version: 1).run(
        task: task,
        root_recording: root,
        context_recording: page_recording,
        initiator: current_user,
        initiator_kind: :user,
        execution_source: :web,
        idempotency_key: "demo:#{task.key}"
      )
    end

    redirect_to root_path, notice: notice_for(result)
  end

  private

  def with_generate_stub
    return yield if RecordingStudioAI.configuration.openai_api_key.present?

    singleton = RecordingStudioAI.singleton_class
    original = singleton.instance_method(:generate)
    controller = self
    singleton.define_method(:generate) { |**kwargs| controller.send(:stubbed_response, **kwargs) }
    yield
  ensure
    singleton&.define_method(:generate, original) if original
  end

  def stubbed_response(**kwargs)
    ai_run = persist_stubbed_ai_run(**kwargs)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: kwargs[:purpose] || "agent_page_librarian",
      text: "Found Getting Started.",
      run: ai_run
    )
  end

  def persist_stubbed_ai_run(**kwargs)
    initiator = kwargs.fetch(:initiator)
    root = kwargs.fetch(:root_recording)
    now = Time.current
    context = kwargs[:context_recording]

    ai_run = RecordingStudioAI::Run.create!(
      operation: "generation",
      purpose: kwargs[:purpose],
      status: "completed",
      root_recording_id: root.id,
      context_recording_id: context&.id,
      initiator_type: initiator.class.name,
      initiator_id: initiator.id.to_s,
      initiator_kind: (kwargs[:initiator_kind] || :user).to_s,
      execution_source: (kwargs[:execution_source] || :web).to_s,
      request_id: kwargs[:request_id],
      metadata: kwargs[:metadata],
      started_at: now,
      completed_at: now,
      custom_tool_invocation_count: 1,
      total_tokens: 1_200,
      latency_ms: 400,
      input_tokens: 900,
      output_tokens: 300
    )
    RecordingStudioAI::CustomToolInvocation.create!(
      run: ai_run,
      tool_key: "find_page",
      tool_version: 1,
      tool_name_snapshot: "Find page",
      status: "completed",
      read_only: true,
      destructive: false,
      requires_confirmation: false,
      idempotent: true,
      confirmation_status: "not_required",
      started_at: now,
      completed_at: now
    )
    ai_run
  end

  def notice_for(result)
    case result
    when RecordingStudioAgents::Results::Completed
      "Found it."
    when RecordingStudioAgents::Results::Blocked
      "Waiting on a confirmation."
    when RecordingStudioAgents::Results::HandoffRequested
      "Needs a reviewer."
    when RecordingStudioAgents::Results::Existing, RecordingStudioAgents::Results::InProgress
      "That attempt is already on record."
    else
      "That run did not finish."
    end
  end
end
