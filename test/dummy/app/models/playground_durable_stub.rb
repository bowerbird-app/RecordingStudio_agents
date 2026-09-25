# frozen_string_literal: true

class PlaygroundDurableStub
  Answer = Struct.new(:probability)
  Choice = Struct.new(:choice, :probabilities)
  Decision = Struct.new(:answers, :error, :run, keyword_init: true) do
    def success?
      error.nil?
    end
  end
  Performance = Struct.new(:status, :result, :error, :run, keyword_init: true) do
    def success?
      status == "completed" && error.nil?
    end

    def awaiting_confirmation?
      false
    end
  end

  def generate(**kwargs)
    if kwargs[:request_id].to_s.end_with?(":answer")
      return text_response(kwargs, "Found Getting Started.")
    end
    return plan_response(kwargs) if kwargs[:purpose].to_s.include?("page_librarian")

    text_response(kwargs, "Finished.")
  end

  def decide(**kwargs)
    call = persist_run(kwargs, operation: "decision", model: "jev-latest")
    state = kwargs[:state].to_s
    if state.include?("list_pages v")
      return decision("list", %w[list find deliver], run: call)
    end
    return decision("find", %w[find deliver], run: call) if state.include?("find_page v")

    decision("deliver", ["deliver"], finished: 0.95, run: call)
  end

  def perform_tool(**kwargs)
    key = kwargs[:tool].to_h[:key] || kwargs[:tool].to_h["key"]
    summary = key.to_s == "list_pages" ? "Listed the pages." : "Found the page."
    criteria = key.to_s == "find_page" ? ["found"] : []
    Performance.new(
      status: "completed",
      result: { "summary" => summary, "findings" => [summary], "meet_criteria" => criteria },
      error: nil,
      run: nil
    )
  end

  private

  def plan_response(kwargs)
    ai_run = persist_run(kwargs)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: kwargs[:purpose],
      text: nil,
      structured_data: {
        "plan" => ["List the pages", "Find the named page", "Answer"],
        "success_criteria" => [{ "id" => "found", "text" => "The named page was found" }],
        "current_objective" => "Find the named page",
        "action_candidates" => [
          {
            "id" => "list",
            "type" => "tool",
            "purpose" => "List the pages in this workspace",
            "tool_key" => "list_pages",
            "tool_version" => 1,
            "arguments" => {}
          },
          {
            "id" => "find",
            "type" => "tool",
            "purpose" => "Find the named page",
            "tool_key" => "find_page",
            "tool_version" => 1,
            "arguments" => { "title" => "Getting Started" }
          },
          { "id" => "deliver", "type" => "deliver", "purpose" => "Answer with the page" }
        ]
      },
      run: ai_run
    )
  end

  def text_response(kwargs, text)
    ai_run = persist_run(kwargs, text: text)
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: kwargs[:purpose],
      text: text,
      run: ai_run
    )
  end

  def decision(choice_id, candidate_ids, finished: 0.1, run: nil)
    probabilities = candidate_ids.to_h { |id| [id, id == choice_id ? 0.9 : 0.05] }
    Decision.new(
      answers: {
        finished: Answer.new(finished),
        progress_made: Answer.new(0.8),
        stuck: Answer.new(0.05),
        needs_reasoning: Answer.new(0.05),
        next_action: Choice.new(choice_id, probabilities)
      },
      error: nil,
      run: run
    )
  end

  def persist_run(kwargs, text: nil, operation: "generation", model: nil)
    initiator = kwargs.fetch(:initiator)
    root = kwargs.fetch(:root_recording)
    now = Time.current
    profile = kwargs[:profile]&.to_s
    ai_run = RecordingStudioAI::Run.create!(
      operation: operation,
      purpose: kwargs[:purpose],
      status: "completed",
      root_recording_id: root.id,
      context_recording_id: kwargs[:context_recording]&.id,
      initiator_type: initiator.class.name,
      initiator_id: initiator.id.to_s,
      initiator_kind: (kwargs[:initiator_kind] || :user).to_s,
      execution_source: (kwargs[:execution_source] || :web).to_s,
      request_id: kwargs[:request_id],
      profile_key: profile,
      resolved_provider: operation == "decision" ? "typesafe" : "gemini",
      resolved_model: model || (profile == "low" ? "gemini-2.5-flash" : "gemini-2.5-pro"),
      metadata: kwargs[:metadata],
      started_at: now,
      completed_at: now,
      custom_tool_invocation_count: 0,
      total_tokens: 1_200,
      latency_ms: 400,
      input_tokens: 900,
      output_tokens: 300
    )
    remember_reply(ai_run, text) if text.present?
    ai_run
  end

  def remember_reply(ai_run, text)
    now = Time.current
    attempt = RecordingStudioAI::Attempt.create!(
      run: ai_run,
      sequence: 1,
      kind: "primary",
      status: "completed",
      started_at: now,
      completed_at: now
    )
    RecordingStudioAI::Response.create!(
      attempt: attempt,
      response_type: "generation",
      content_text: text,
      content_type: "text/plain",
      complete: true,
      expires_at: now + RecordingStudioAI.configuration.response_retention_period
    )
  end
end
