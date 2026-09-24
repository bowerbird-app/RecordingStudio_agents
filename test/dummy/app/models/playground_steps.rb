# frozen_string_literal: true

class PlaygroundSteps
  Entry = Data.define(:id, :title, :badge, :badge_style, :body, :arguments_text)

  def self.for(run, reply_text: nil)
    build(
      RecordingStudioAgents::Progress.for(run),
      invocations_for(run),
      failure_message: run.failure_message,
      reply_text: reply_text
    )
  end

  def self.build(steps, invocations, failure_message:, reply_text:)
    tool_index = 0
    entries = steps.each_with_index.map do |step, index|
      invocation = invocations[tool_index] if step.kind == :tool
      tool_index += 1 if step.kind == :tool
      Entry.new(
        id: "playground-step-#{index}",
        title: title_for(step),
        badge: step.badge,
        badge_style: step.badge_style,
        body: body_for(step, invocation, failure_message),
        arguments_text: arguments_text(invocation)
      )
    end
    entries << reply_entry(reply_text) if reply_text.present?
    entries
  end

  def self.body_for(step, invocation, failure_message)
    case step.kind
    when :tool
      tool_body(step, invocation)
    when :knowledge
      "Looked through this workspace."
    when :running
      "Still going."
    when :confirmation
      "Waiting for a yes."
    when :handoff
      "Asked a reviewer to take it from here."
    when :finished
      "The run finished."
    when :failed
      failure_message.presence || "This one stopped."
    else
      step.label
    end
  end

  def self.title_for(step)
    return "Wrapped up" if step.kind == :finished

    step.label
  end

  def self.tool_body(step, invocation)
    return "Waiting for a yes before using #{step.label}." if step.status == :waiting
    return invocation.error_message if invocation&.error_message.present?

    summary = invocation&.result_summary.to_s.strip
    return summary if summary.present? && !summary.start_with?("{", "[")

    "Used #{step.label}."
  end

  def self.arguments_text(invocation)
    arguments = read_arguments(invocation)
    return if arguments.blank?

    JSON.pretty_generate(arguments)
  end

  def self.read_arguments(invocation)
    return {} unless invocation.respond_to?(:metadata)

    metadata = invocation.metadata
    return {} unless metadata.is_a?(Hash)

    arguments = metadata["arguments"] || metadata[:arguments]
    arguments.is_a?(Hash) ? arguments.deep_stringify_keys : {}
  end

  def self.reply_entry(reply_text)
    Entry.new(
      id: "playground-reply",
      title: "Reply",
      badge: "Done",
      badge_style: :success,
      body: reply_text,
      arguments_text: nil
    )
  end

  def self.invocations_for(run)
    id = run.recording_studio_ai_run_id
    return [] if id.blank?

    ai_run = RecordingStudioAI::Run.find_by(id: id)
    return [] if ai_run.nil? || !ai_run.respond_to?(:custom_tool_invocations)

    ai_run.custom_tool_invocations.order(:created_at, :id).reject do |invocation|
      invocation.tool_key.to_s == RecordingStudioAgents::Handoffs::INTERNAL_TOOL_KEY.to_s
    end
  rescue StandardError
    []
  end

  private_class_method :body_for, :title_for, :tool_body, :arguments_text, :read_arguments, :reply_entry, :invocations_for
end
