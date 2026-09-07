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
    response = stubbed_response
    singleton.define_method(:generate) { |**_kwargs| response }
    yield
  ensure
    singleton&.define_method(:generate, original) if original
  end

  def stubbed_response
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_page_librarian",
      text: "Found Getting Started.",
      run: Struct.new(:id).new(SecureRandom.random_number(2**31 - 1) + 1)
    )
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
