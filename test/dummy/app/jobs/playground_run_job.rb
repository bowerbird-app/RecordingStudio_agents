# frozen_string_literal: true

class PlaygroundRunJob < ApplicationJob
  FIND_PAGE = { key: :find_page, version: 1 }.freeze

  def perform(
    idempotency_key,
    task_key,
    root_recording_id,
    user_id,
    agent_key,
    agent_version,
    goal,
    context,
    pack,
    extra_skills,
    skills = nil,
    tools = nil
  )
    previous_actor = Current.actor
    root = RecordingStudio::Recording.find(root_recording_id)
    user = User.find(user_id)
    Current.actor = user
    task = RecordingStudioAgents::TaskInput.new(key: task_key, goal: goal, context: context || {})
    run_agent(root, user, task, idempotency_key, agent_key, agent_version, pack, extra_skills, skills, tools)
  rescue RecordingStudioAgents::Error => error
    remember_error(root_recording_id, idempotency_key, error)
  ensure
    Current.actor = previous_actor
  end

  private

  def run_agent(root, user, task, idempotency_key, agent_key, agent_version, pack, extra_skills, skills, tools)
    runner = lambda do
      RecordingStudioAgents.agent(agent_key, version: agent_version).run(
        **run_arguments(root, user, task, idempotency_key, pack, extra_skills, skills, tools)
      )
    end

    if generative_provider_configured?
      runner.call
    else
      DummyGenerateStub.with_hook(method(:stubbed_response)) { runner.call }
    end
  end

  def run_arguments(root, user, task, idempotency_key, pack, extra_skills, skills, tools)
    arguments = {
      task: task,
      root_recording: root,
      initiator: user,
      initiator_kind: :user,
      execution_source: :web,
      context_recording: nil,
      idempotency_key: idempotency_key,
      pack: pack_for(pack),
      extra_skills: extras_for(extra_skills)
    }
    arguments[:skills] = extras_for(skills) unless skills.nil?
    arguments[:tools] = extras_for(tools) unless tools.nil?
    arguments
  end

  def pack_for(pack)
    return if pack.blank?

    key, version = pack
    { key => Integer(version) }
  end

  def extras_for(pairs)
    Array(pairs).to_h { |key, version| [ key, Integer(version) ] }
  end

  def generative_provider_configured?
    configuration = RecordingStudioAI.configuration
    configuration.gemini_api_key.present? || configuration.openai_api_key.present?
  end

  def stubbed_response(**kwargs)
    ai_run = persist_stubbed_ai_run(**kwargs)
    if Array(kwargs[:custom_tools]).include?(FIND_PAGE)
      remember_find_page_turns(ai_run)
    else
      remember_reply(ai_run, sequence: 1, kind: "primary", text: "Finished.")
    end
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: kwargs[:purpose],
      text: "Finished.",
      run: ai_run
    )
  end

  def persist_stubbed_ai_run(**kwargs)
    initiator = kwargs.fetch(:initiator)
    root = kwargs.fetch(:root_recording)
    now = Time.current
    context = kwargs[:context_recording]
    find_page = Array(kwargs[:custom_tools]).include?(FIND_PAGE)

    RecordingStudioAI::Run.create!(
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
      custom_tool_invocation_count: find_page ? 1 : 0,
      total_tokens: 1_200,
      latency_ms: 400,
      input_tokens: 900,
      output_tokens: 300
    )
  end

  def remember_find_page_turns(ai_run)
    asked = remember_reply(ai_run, sequence: 1, kind: "primary", text: nil)
    answered = remember_reply(ai_run, sequence: 2, kind: "continuation", text: "Finished.")
    now = Time.current
    RecordingStudioAI::CustomToolInvocation.create!(
      run: ai_run,
      requested_by_attempt: asked,
      continued_by_attempt: answered,
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
      completed_at: now,
      metadata: {
        "arguments" => { "title" => "Getting Started" },
        "result" => { "found" => true, "title" => "Getting Started" }
      }
    )
  end

  def remember_reply(ai_run, sequence:, kind:, text:)
    now = Time.current
    attempt = RecordingStudioAI::Attempt.create!(
      run: ai_run,
      sequence: sequence,
      kind: kind,
      status: "completed",
      started_at: now,
      completed_at: now
    )
    return attempt if text.blank?

    RecordingStudioAI::Response.create!(
      attempt: attempt,
      response_type: "generation",
      content_text: text,
      content_type: "text/plain",
      complete: true,
      expires_at: now + RecordingStudioAI.configuration.response_retention_period
    )
    attempt
  end

  def remember_error(root_recording_id, idempotency_key, error)
    return if RecordingStudioAgents::AgentRun.exists?(
      root_recording_id: root_recording_id,
      idempotency_key: idempotency_key
    )

    Rails.cache.write("playground:#{idempotency_key}:error", error.message)
  end
end
