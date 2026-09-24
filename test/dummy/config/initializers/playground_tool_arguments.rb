# frozen_string_literal: true

# Tool invocations keep a result summary, not the arguments that were sent.
# The playground reads this copy from the invocation metadata.
module PlaygroundToolArguments
  def create!(run, requesting_attempt, tool_call, definition)
    invocation = super
    arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : nil
    return invocation unless arguments.is_a?(Hash) && arguments.any?

    stored = invocation.metadata.is_a?(Hash) ? invocation.metadata.deep_stringify_keys : {}
    invocation.update!(metadata: stored.merge("arguments" => arguments.deep_stringify_keys))
    invocation
  end
end

Rails.application.config.to_prepare do
  records = RecordingStudioAI::Orchestration::CustomToolRecords
  next if records.ancestors.include?(PlaygroundToolArguments)

  records.prepend(PlaygroundToolArguments)
end
