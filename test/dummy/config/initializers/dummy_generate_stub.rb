# frozen_string_literal: true

# Request-scoped generate hook for the dummy demo when no generative provider key is set.
# Tests should use RecordingStudioAI.stub(:generate, ...) instead of define_method.
module DummyGenerateStub
  THREAD_KEY = :dummy_generate

  def generate(**kwargs, &block)
    hook = Thread.current[THREAD_KEY]
    return hook.generate(**kwargs, &block) if hook.respond_to?(:generate)
    return hook.call(**kwargs, &block) if hook.respond_to?(:call)

    super
  end

  def decide(**kwargs)
    hook = Thread.current[THREAD_KEY]
    return hook.decide(**kwargs) if hook.respond_to?(:decide)

    super
  end

  def perform_tool(**kwargs)
    hook = Thread.current[THREAD_KEY]
    return hook.perform_tool(**kwargs) if hook.respond_to?(:perform_tool)

    super
  rescue NoMethodError
    raise RecordingStudioAgents::ConfigurationError,
          "Tool steps need RecordingStudioAI.perform_tool. This Recording Studio AI gem does not provide it."
  end

  def self.with_hook(hook)
    Thread.current[THREAD_KEY] = hook
    yield
  ensure
    Thread.current[THREAD_KEY] = nil
  end
end

RecordingStudioAI.singleton_class.prepend(DummyGenerateStub)
