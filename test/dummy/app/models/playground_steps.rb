# frozen_string_literal: true

class PlaygroundSteps
  Entry = Data.define(:id, :title, :badge, :badge_style, :exchange)
  Turn = Data.define(:status, :text, :error_message, :asked, :heard)
  ToolNote = Data.define(:name, :key, :value)

  HANDOFF_KEY = RecordingStudioAgents::Handoffs::INTERNAL_TOOL_KEY.to_s
  BADGES = {
    "completed" => [ "Done", :success ],
    "failed" => [ "Failed", :danger ],
    "cancelled" => [ "Failed", :danger ]
  }.freeze

  def self.for(run, initiator:, context: nil)
    return entries_for_agent_steps(run) if run.agent_steps.exists?

    build(
      turns_for(run, initiator),
      instruction: run.task.goal,
      context: context,
      failure_message: run.failure_message,
      status: run.status
    )
  end

  def self.entries_for_agent_steps(run)
    objective = objective_for(run)
    run.agent_steps.order(:sequence).each_with_index.map do |agent_step, index|
      badge, style = badge_for(agent_step.status == "completed" ? "completed" : agent_step.status)
      Entry.new(
        id: "playground-step-#{index}",
        title: title_for_agent_step(agent_step),
        badge: badge,
        badge_style: style,
        exchange: dump(
          "action" => agent_step.action_type,
          "now" => objective,
          "observation" => agent_step.observation_summary,
          "progress" => agent_step.progress_made
        )
      )
    end
  end

  def self.objective_for(run)
    return unless run.respond_to?(:working_state_json)

    RecordingStudioAgents::WorkingState.load(run.working_state_json).current_objective
  rescue StandardError
    nil
  end

  def self.title_for_agent_step(agent_step)
    case agent_step.action_type
    when "reason" then agent_step.sequence.to_i > 1 ? "New plan" : "Plan"
    when "decide" then "Checked in"
    when "tool" then agent_step.tool_key.to_s.tr("_", " ").sub(/\A./, &:upcase)
    when "deliver" then "Answer"
    when "handoff" then "Asked for a reviewer"
    else "On it"
    end
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

      ToolNote.new(
        name: tool_name(invocation),
        key: invocation.tool_key.to_s,
        value: metadata_value(invocation, metadata_key)
      )
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
      exchange: exchange_for(turn, instruction, context, failure_message)
    )
  end

  def self.failure_entry(instruction, context, failure_message)
    message = failure_message.to_s.strip
    Entry.new(
      id: "playground-step-0",
      title: "Did not finish",
      badge: "Failed",
      badge_style: :danger,
      exchange: dump(
        "input" => instruction_input(instruction, context),
        "output" => { "error" => message.presence || "Did not finish." }
      )
    )
  end

  def self.exchange_for(turn, instruction, context, failure_message)
    dump(
      "input" => input_for(turn, instruction, context),
      "output" => output_for(turn, failure_message)
    )
  end

  def self.input_for(turn, instruction, context)
    heard = tool_hash(turn.heard)
    return heard if heard.present?

    instruction_input(instruction, context)
  end

  def self.instruction_input(instruction, context)
    payload = {}
    text = instruction.to_s.strip
    payload["instruction"] = text if text.present?
    extra = context_value(context)
    payload["context"] = extra unless extra.nil?
    payload
  end

  def self.output_for(turn, failure_message)
    payload = {}
    reply = turn.text.to_s.strip
    payload["text"] = reply if reply.present?
    payload.merge!(tool_hash(turn.asked))
    return payload if payload.present?

    message = turn.error_message.to_s.strip
    message = failure_message.to_s.strip if message.blank?
    return { "error" => message } if message.present? && failed?(turn.status)

    nil
  end

  def self.tool_hash(notes)
    notes.each_with_object({}) do |note, payload|
      payload[note.key] = note.value.nil? ? {} : note.value
    end
  end

  def self.context_value(context)
    extra = context.to_s.strip
    return if extra.blank?

    JSON.parse(extra)
  rescue JSON::ParserError
    extra
  end

  def self.dump(payload)
    JSON.pretty_generate(payload)
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

  def self.tool_name(invocation)
    snapshot = invocation.tool_name_snapshot
    return snapshot if snapshot.present?

    invocation.tool_key.to_s.tr("_", " ").sub(/\A./, &:upcase)
  end

  def self.metadata_value(invocation, key)
    if %w[arguments result].include?(key) && invocation.respond_to?(key)
      stored = invocation.public_send(key)
      return stored unless stored.nil?
    end

    metadata = invocation.metadata
    return nil unless metadata.is_a?(Hash) && metadata.key?(key)

    metadata[key]
  end

  def self.failed?(status)
    %w[failed cancelled].include?(status.to_s)
  end

  private_class_method :entries_for_agent_steps, :objective_for, :title_for_agent_step,
    :turns_for, :ai_run_for, :linked_ai_run, :visible_invocations, :turn_for, :notes_for,
    :response_text, :entry_for, :failure_entry, :exchange_for, :input_for, :instruction_input,
    :output_for, :tool_hash, :context_value, :dump, :title_for, :badge_for, :tool_name,
    :metadata_value, :failed?
end
