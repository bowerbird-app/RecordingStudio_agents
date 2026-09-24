# frozen_string_literal: true

class PlaygroundSteps
  Entry = Data.define(:id, :title, :badge, :badge_style, :given, :returned)

  def self.for(run, reply_text: nil, context: nil)
    build(
      RecordingStudioAgents::Progress.for(run),
      failure_message: run.failure_message,
      reply_text: reply_text,
      instruction: run.task.goal,
      context: context
    )
  end

  def self.build(steps, failure_message:, reply_text:, instruction:, context: nil)
    given = given_text(instruction, context)
    returned = returned_text(reply_text, failure_message)
    entries = steps.each_with_index.map do |step, index|
      Entry.new(
        id: "playground-step-#{index}",
        title: title_for(step),
        badge: step.badge,
        badge_style: step.badge_style,
        given: given,
        returned: returned
      )
    end
    entries << reply_entry(given, returned) if reply_text.to_s.strip.present?
    entries
  end

  def self.given_text(instruction, context)
    text = instruction.to_s.strip
    extra = context.to_s.strip
    return text if extra.blank?

    "#{text}\n\n#{extra}"
  end

  def self.returned_text(reply_text, failure_message)
    reply = reply_text.to_s.strip
    return reply if reply.present?

    failure = failure_message.to_s.strip
    return failure if failure.present?

    "Still going."
  end

  def self.title_for(step)
    return "Wrapped up" if step.kind == :finished

    step.label
  end

  def self.reply_entry(given, returned)
    Entry.new(
      id: "playground-reply",
      title: "Reply",
      badge: "Done",
      badge_style: :success,
      given: given,
      returned: returned
    )
  end

  private_class_method :given_text, :returned_text, :title_for, :reply_entry
end
