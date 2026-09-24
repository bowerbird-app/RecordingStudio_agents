# frozen_string_literal: true

class PlaygroundSteps
  Entry = Data.define(:id, :title, :badge, :badge_style, :given, :returned)
  Turn = Data.define(:status, :text, :error_message, :asked, :heard)
  ToolNote = Data.define(:name, :body)

  HANDOFF_KEY = RecordingStudioAgents::Handoffs::INTERNAL_TOOL_KEY.to_s
  BADGES = {
    "completed" => [ "Done", :success ],
    "failed" => [ "Failed", :danger ],
    "cancelled" => [ "Failed", :danger ]
  }.freeze

  def self.for(run, initiator:, context: nil)
    build(
      turns_for(run, initiator),
      instruction: run.task.goal,
      context: context,
      failure_message: run.failure_message,
      status: run.status
    )
  end

  def self.build(turns, instruction:, context: nil, failure_message: nil, status: nil)
    if turns.empty?
      return [] unless failed?(status)

      return [ failure_entry(instruction, context, failure_message) ]
    end

    turns.each_with_index.map do |turn, index|
      entry_for(turn, index, instruction, context, failure_message)
    end
  end

  def self.turns_for(run, initiator)
    ai_run = ai_run_for(run)
    return [] if ai_run.nil?

    notes = visible_invocations(ai_run)
    ai_run.attempts.order(:sequence).filter_map do |attempt|
      turn_for(attempt, notes, initiator)
    end
  end

  def self.ai_run_for(run)
    linked = linked_ai_run(run)
    return linked if linked

    RecordingStudioAgents::Ai.find_run(
      request_id: RecordingStudioAgents::Ai.request_id_for(run)
    )
  end

  def self.linked_ai_run(run)
    return if run.recording_studio_ai_run_id.blank?

    RecordingStudioAI::Run.find_by(id: run.recording_studio_ai_run_id)
  end

  def self.visible_invocations(ai_run)
    ai_run.custom_tool_invocations.reject { |invocation| invocation.tool_key == HANDOFF_KEY }
  end

  def self.turn_for(attempt, invocations, initiator)
    asked = notes_for(invocations, :requested_by_attempt_id, attempt.id, "arguments")
    heard = notes_for(invocations, :continued_by_attempt_id, attempt.id, "result")
    text = response_text(attempt, initiator)
    return if text.blank? && asked.empty? && heard.empty? && attempt.status == "completed"

    Turn.new(status: attempt.status, text: text, error_message: attempt.error_message, asked: asked, heard: heard)
  end

  def self.notes_for(invocations, link, attempt_id, metadata_key)
    invocations.filter_map do |invocation|
      next unless invocation.public_send(link) == attempt_id

      ToolNote.new(name: tool_name(invocation), body: metadata_body(invocation, metadata_key))
    end
  end

  def self.response_text(attempt, initiator)
    response = attempt.response
    return if response.nil? || initiator.nil?

    payload = RecordingStudioAI.read_retained_response(response: response, initiator: initiator)
    payload[:content_text] if payload.is_a?(Hash)
  rescue StandardError
    nil
  end

  def self.entry_for(turn, index, instruction, context, failure_message)
    badge, style = badge_for(turn.status)
    Entry.new(
      id: "playground-step-#{index}",
      title: title_for(turn),
      badge: badge,
      badge_style: style,
      given: given_for(turn, instruction, context),
      returned: returned_for(turn, failure_message)
    )
  end

  def self.failure_entry(instruction, context, failure_message)
    message = failure_message.to_s.strip
    Entry.new(
      id: "playground-step-0",
      title: "Did not finish",
      badge: "Failed",
      badge_style: :danger,
      given: instruction_text(instruction, context),
      returned: message.presence || "Did not finish."
    )
  end

  def self.given_for(turn, instruction, context)
    heard = notes_text(turn.heard)
    return heard if heard.present?

    instruction_text(instruction, context)
  end

  def self.returned_for(turn, failure_message)
    parts = []
    reply = turn.text.to_s.strip
    parts << reply if reply.present?
    asked = notes_text(turn.asked)
    parts << asked if asked.present?
    return parts.join("\n\n") if parts.any?

    message = turn.error_message.to_s.strip
    message = failure_message.to_s.strip if message.blank?
    return message if message.present? && failed?(turn.status)

    "Still going."
  end

  def self.title_for(turn)
    names = turn.asked.map(&:name).uniq
    return names.join(", ") if names.any?
    return "Reply" if turn.text.to_s.strip.present?
    return "Did not finish" if failed?(turn.status)

    "On it"
  end

  def self.badge_for(status)
    BADGES.fetch(status.to_s, [ "Working", :info ])
  end

  def self.instruction_text(instruction, context)
    text = instruction.to_s.strip
    extra = context.to_s.strip
    return text if extra.blank?

    "#{text}\n\n#{extra}"
  end

  def self.notes_text(notes)
    notes.filter_map { |note| [ note.name, note.body ].compact_blank.join("\n").presence }.join("\n\n")
  end

  def self.tool_name(invocation)
    snapshot = invocation.tool_name_snapshot
    return snapshot if snapshot.present?

    invocation.tool_key.to_s.tr("_", " ").sub(/\A./, &:upcase)
  end

  def self.metadata_body(invocation, key)
    metadata = invocation.metadata
    return unless metadata.is_a?(Hash)

    format_body(metadata[key])
  end

  def self.format_body(value)
    return if value.nil?
    return if value.respond_to?(:empty?) && value.empty?

    return JSON.pretty_generate(value) if value.is_a?(Hash) || value.is_a?(Array)

    value.to_s
  end

  def self.failed?(status)
    %w[failed cancelled].include?(status.to_s)
  end

  private_class_method :turns_for, :ai_run_for, :linked_ai_run, :visible_invocations, :turn_for, :notes_for,
    :response_text, :entry_for, :failure_entry, :given_for, :returned_for, :title_for,
    :badge_for, :instruction_text, :notes_text, :tool_name, :metadata_body, :format_body, :failed?
end
