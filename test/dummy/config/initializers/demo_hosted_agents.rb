# frozen_string_literal: true

# Local stand-in so the dummy chat page can stream without an OpenAI key.
# Requests still enter through RecordingStudioAI::Agents.
module DemoHostedAgents
  module_function

  def install!
    agents = RecordingStudioAI::Agents
    agents.define_singleton_method(:create_session) { |**kwargs| DemoHostedAgents.create_session(**kwargs) }
    agents.define_singleton_method(:send_input) { |**kwargs| DemoHostedAgents.send_input(**kwargs) }
    agents.define_singleton_method(:stream) { |**kwargs, &block| DemoHostedAgents.stream(**kwargs, &block) }
    agents.define_singleton_method(:cancel) { |**kwargs| DemoHostedAgents.cancel(**kwargs) }
    agents.define_singleton_method(:delete_session) { |**kwargs| DemoHostedAgents.delete_session(**kwargs) }
    agents.define_singleton_method(:recover) { |**kwargs| DemoHostedAgents.recover(**kwargs) }
  end

  def create_session(**kwargs)
    session = build(kwargs[:input])
    remember(session.provider_session_id, kwargs[:input])
    session
  end

  def send_input(**kwargs)
    remember(kwargs.fetch(:session).provider_session_id, kwargs[:input])
    kwargs.fetch(:session)
  end

  def stream(**kwargs, &block)
    record = sessions[kwargs.fetch(:session).provider_session_id]
    return if record.nil?

    speak(record, &block)
    record
  end

  def cancel(**kwargs)
    record = sessions[kwargs.fetch(:session).provider_session_id]
    record[:cancelled] = true if record
    kwargs.fetch(:session)
  end

  def delete_session(**kwargs)
    sessions.delete(kwargs.fetch(:session).provider_session_id)
    kwargs.fetch(:session)
  end

  def recover(**kwargs)
    record = sessions[kwargs.fetch(:session).provider_session_id]
    RecordingStudioAI::Agents::Recovery.new(session: kwargs.fetch(:session), turn: nil, items: items_for(record))
  end

  def sessions
    @sessions ||= {}
  end

  def build(input)
    RecordingStudioAI::Agents::Session.new(
      provider: :openai, provider_session_id: "demo_#{SecureRandom.hex(4)}", model: "demo", profile: "medium",
      status: "in_progress"
    ).tap { sessions[_1.provider_session_id] = { input: input.to_s, cancelled: false, reply: nil } }
  end

  def remember(id, input)
    sessions[id] ||= { cancelled: false }
    sessions[id][:input] = input.to_s
    sessions[id][:cancelled] = false
    sessions[id][:reply] = nil
  end

  def speak(record)
    reply = "Noted. #{record[:input]}"
    reply.split(/(\s+)/).each do |piece|
      if record[:cancelled]
        yield event("cancelled")
        return
      end

      sleep 0.6
      yield event("text_delta", text_delta: piece)
    end
    record[:reply] = reply
    yield event("message_completed", text: reply)
    yield event("turn_completed")
  end

  def items_for(record)
    return [] if record.nil? || record[:reply].blank?

    [RecordingStudioAI::Agents::Item.new(id: "demo-item", role: "assistant", text: record[:reply], status: "done")]
  end

  def event(type, text_delta: nil, text: nil)
    RecordingStudioAI::Providers::StreamEvent.new(type: type, text_delta: text_delta, text: text)
  end
end

DemoHostedAgents.install! if Rails.env.development?
