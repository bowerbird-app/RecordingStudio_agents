# frozen_string_literal: true

# Tool invocations keep a result summary, not the arguments or the result body.
# The playground reads both from the invocation metadata.
module PlaygroundToolArguments
  def create!(run, requesting_attempt, tool_call, definition)
    invocation = super
    arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : nil
    remember(invocation, "arguments", arguments)
  end

  def complete!(invocation, result, continuation)
    super
    remember(invocation, "result", result)
  end

  private

  def remember(invocation, key, value)
    return invocation if invocation.nil?
    return invocation if value.nil?
    return invocation if value.respond_to?(:empty?) && value.empty?

    stored = invocation.reload.metadata.is_a?(Hash) ? invocation.metadata.deep_stringify_keys : {}
    invocation.update!(metadata: stored.merge(key => json_safe(value)))
    invocation
  end

  def json_safe(value)
    JSON.parse(JSON.generate(value))
  rescue JSON::GeneratorError, TypeError
    value.to_s
  end
end

Rails.application.config.to_prepare do
  records = RecordingStudioAI::Orchestration::CustomToolRecords
  next if records.ancestors.include?(PlaygroundToolArguments)

  records.prepend(PlaygroundToolArguments)
end
