# frozen_string_literal: true

# Request-scoped generate hook for the dummy demo when no provider key is set.
# Tests should use RecordingStudioAI.stub(:generate, ...) instead of define_method.
module DummyGenerateStub
  THREAD_KEY = :dummy_generate

  def generate(**kwargs, &block)
    hook = Thread.current[THREAD_KEY]
    return hook.call(**kwargs, &block) if hook.respond_to?(:call)

    super
  end

  def self.with_hook(hook)
    Thread.current[THREAD_KEY] = hook
    yield
  ensure
    Thread.current[THREAD_KEY] = nil
  end
end

RecordingStudioAI.singleton_class.prepend(DummyGenerateStub)
