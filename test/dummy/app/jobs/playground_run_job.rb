# frozen_string_literal: true

class PlaygroundRunJob < ApplicationJob
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
    tools = nil,
    profile = nil
  )
    previous_actor = Current.actor
    root = RecordingStudio::Recording.find(root_recording_id)
    user = User.find(user_id)
    Current.actor = user
    task = RecordingStudioAgents::TaskInput.new(key: task_key, goal: goal, context: context || {})
    run_agent(
      root, user, task, idempotency_key, agent_key, agent_version, pack, extra_skills, skills, tools, profile
    )
  rescue RecordingStudioAgents::Error => error
    remember_error(root_recording_id, idempotency_key, error)
  ensure
    Current.actor = previous_actor
  end

  private

  def run_agent(root, user, task, idempotency_key, agent_key, agent_version, pack, extra_skills, skills, tools, profile)
    runner = lambda do
      RecordingStudioAgents.agent(agent_key, version: agent_version).run(
        **run_arguments(root, user, task, idempotency_key, pack, extra_skills, skills, tools, profile)
      )
    end

    if generative_provider_configured?
      runner.call
    else
      DummyGenerateStub.with_hook(PlaygroundDurableStub.new) { runner.call }
    end
  end

  def run_arguments(root, user, task, idempotency_key, pack, extra_skills, skills, tools, profile)
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
    arguments[:profile] = profile if profile.present?
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

  def remember_error(root_recording_id, idempotency_key, error)
    return if RecordingStudioAgents::AgentRun.exists?(
      root_recording_id: root_recording_id,
      idempotency_key: idempotency_key
    )

    Rails.cache.write("playground:#{idempotency_key}:error", error.message)
  end
end
