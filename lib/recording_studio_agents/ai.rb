# frozen_string_literal: true

require "digest"

module RecordingStudioAgents
  module Ai
    REQUEST_ID_PREFIX = "recording-studio-agents:"

    module_function

    def authorize!(request:, program:)
      RecordingStudioAI::Authorization.authorize!(
        :execute,
        attribution: attribution_for(request),
        context: {
          operation: "agent_run",
          agent_key: program.key,
          agent_version: program.version
        }
      )
    end

    PLAN_SCHEMA = {
      "type" => "object",
      "additionalProperties" => false,
      "required" => %w[plan success_criteria current_objective action_candidates],
      "properties" => {
        "plan" => { "type" => "array", "items" => { "type" => "string" } },
        "success_criteria" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => %w[id text],
            "properties" => {
              "id" => { "type" => "string" },
              "text" => { "type" => "string" }
            }
          }
        },
        "current_objective" => { "type" => "string" },
        "action_candidates" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => %w[id type purpose],
            "properties" => {
              "id" => { "type" => "string" },
              "type" => { "type" => "string", "enum" => %w[tool deliver handoff] },
              "purpose" => { "type" => "string" },
              "tool_key" => { "type" => "string" },
              "tool_version" => { "type" => "integer" },
              "arguments" => { "type" => "object" },
              "handoff_key" => { "type" => "string" },
              "handoff_version" => { "type" => "integer" }
            }
          }
        }
      }
    }.freeze

    OBSERVE_SCHEMA = {
      "type" => "object",
      "additionalProperties" => false,
      "required" => %w[summary],
      "properties" => {
        "summary" => { "type" => "string" },
        "add_findings" => { "type" => "array", "items" => { "type" => "string" } },
        "add_completed" => { "type" => "array", "items" => { "type" => "string" } },
        "add_failed" => { "type" => "array", "items" => { "type" => "string" } },
        "add_open_questions" => { "type" => "array", "items" => { "type" => "string" } },
        "meet_criteria" => { "type" => "array", "items" => { "type" => "string" } },
        "set_current_objective" => { "type" => "string" }
      }
    }.freeze

    COMPACT_SCHEMA = {
      "type" => "object",
      "additionalProperties" => false,
      "properties" => {
        "replace_plan" => { "type" => "array", "items" => { "type" => "string" } },
        "set_current_objective" => { "type" => "string" },
        "add_findings" => { "type" => "array", "items" => { "type" => "string" } },
        "add_completed" => { "type" => "array", "items" => { "type" => "string" } },
        "add_failed" => { "type" => "array", "items" => { "type" => "string" } },
        "add_open_questions" => { "type" => "array", "items" => { "type" => "string" } }
      }
    }.freeze

    def generate(invocation:, run:, lease_token:)
      plan(invocation: invocation, run: run, lease_token: lease_token)
    end

    def plan(invocation:, run:, lease_token:, prompt: nil, suffix: nil)
      RecordingStudioAI.generate(
        prompt: prompt || invocation.goal,
        system_instruction: "#{invocation.system_instruction}\n\n#{planning_note(invocation)}",
        custom_tools: [],
        schema: PLAN_SCHEMA,
        purpose: invocation.purpose,
        profile: invocation.profile,
        root_recording: invocation.root_recording,
        context_recording: invocation.context_recording,
        initiator: invocation.initiator,
        initiator_kind: invocation.initiator_kind,
        executor: invocation.executor,
        execution_source: invocation.execution_source,
        request_id: request_id_for(run, suffix),
        metadata: lease_metadata(run, lease_token)
      )
    end

    def decide(invocation:, run:, lease_token:, state:, questions:, suffix:)
      RecordingStudioAI.decide(
        state: state,
        questions: questions,
        purpose: invocation.purpose,
        profile: RecordingStudioAgents.configuration.controller_profile,
        root_recording: invocation.root_recording,
        context_recording: invocation.context_recording,
        initiator: invocation.initiator,
        initiator_kind: invocation.initiator_kind,
        executor: invocation.executor,
        execution_source: invocation.execution_source,
        request_id: request_id_for(run, suffix),
        metadata: lease_metadata(run, lease_token)
      )
    end

    def fill_arguments(invocation:, run:, lease_token:, prompt:, schema:, suffix:)
      RecordingStudioAI.generate(
        prompt: prompt,
        system_instruction: "#{invocation.system_instruction}\n\nReturn only the arguments object for this tool.",
        custom_tools: [],
        schema: schema,
        purpose: invocation.purpose,
        profile: invocation.profile,
        root_recording: invocation.root_recording,
        context_recording: invocation.context_recording,
        initiator: invocation.initiator,
        initiator_kind: invocation.initiator_kind,
        executor: invocation.executor,
        execution_source: invocation.execution_source,
        request_id: request_id_for(run, suffix),
        metadata: lease_metadata(run, lease_token)
      )
    end

    def observe(invocation:, run:, lease_token:, prompt:, suffix:)
      RecordingStudioAI.generate(
        prompt: prompt,
        system_instruction: "Return only the state delta for this tool result.",
        custom_tools: [],
        schema: OBSERVE_SCHEMA,
        purpose: invocation.purpose,
        profile: RecordingStudioAgents.configuration.controller_profile,
        root_recording: invocation.root_recording,
        context_recording: invocation.context_recording,
        initiator: invocation.initiator,
        initiator_kind: invocation.initiator_kind,
        executor: invocation.executor,
        execution_source: invocation.execution_source,
        request_id: request_id_for(run, suffix),
        metadata: lease_metadata(run, lease_token)
      )
    end

    def synthesize(invocation:, run:, lease_token:, state:)
      RecordingStudioAI.generate(
        prompt: ContextBuilder.for_synthesis(state: state),
        system_instruction: invocation.system_instruction,
        custom_tools: [],
        purpose: invocation.purpose,
        profile: invocation.profile,
        root_recording: invocation.root_recording,
        context_recording: invocation.context_recording,
        initiator: invocation.initiator,
        initiator_kind: invocation.initiator_kind,
        executor: invocation.executor,
        execution_source: invocation.execution_source,
        request_id: request_id_for(run, "answer"),
        metadata: lease_metadata(run, lease_token)
      )
    end

    def compact_state(invocation:, run:, lease_token:, state:, suffix:)
      RecordingStudioAI.generate(
        prompt: ContextBuilder.for_reasoner(state: state, menu: ActionMenu.new, signals: []),
        system_instruction: "Return only the state delta that keeps the goal, success criteria, " \
                            "important findings, completed work, failed approaches, open questions, " \
                            "and the current objective.",
        custom_tools: [],
        schema: COMPACT_SCHEMA,
        purpose: invocation.purpose,
        profile: :low,
        root_recording: invocation.root_recording,
        context_recording: invocation.context_recording,
        initiator: invocation.initiator,
        initiator_kind: invocation.initiator_kind,
        executor: invocation.executor,
        execution_source: invocation.execution_source,
        request_id: request_id_for(run, suffix),
        metadata: lease_metadata(run, lease_token)
      )
    end

    def perform_tool(invocation:, run:, candidate:, sequence:, resume:)
      unless RecordingStudioAI.respond_to?(:perform_tool)
        raise ConfigurationError,
              "Tool steps need RecordingStudioAI.perform_tool. This Recording Studio AI gem does not provide it."
      end

      RecordingStudioAI.perform_tool(
        tool: { key: candidate.tool_key.to_sym, version: candidate.tool_version },
        arguments: resume ? nil : candidate.arguments,
        resume: resume,
        purpose: invocation.purpose,
        root_recording: invocation.root_recording,
        context_recording: invocation.context_recording,
        initiator: invocation.initiator,
        initiator_kind: invocation.initiator_kind,
        executor: invocation.executor,
        execution_source: invocation.execution_source,
        request_id: "#{request_id_for(run)}:tool:#{sequence}",
        metadata: { "agent_run_id" => run.id, "argument_digest" => candidate.argument_digest }
      )
    end

    def request_id_for(run, suffix = nil)
      base = "#{REQUEST_ID_PREFIX}#{run.id}"
      return base if suffix.nil? || suffix.to_s.empty?

      "#{base}:#{suffix}"
    end

    def planning_note(invocation)
      catalog = tool_catalog(invocation)
      note = [
        "Plan the work. Put the next actions in action_candidates.",
        "A tool candidate needs type tool, tool_key, tool_version, purpose, and an arguments object.",
        "Fill each arguments object with the parameters listed for that tool.",
        "Include a deliver candidate when the answer can be written. This step returns the plan only."
      ].join(" ")
      return "#{note} No tools are allowed." if catalog.empty?

      "#{note}\n\n#{catalog}"
    end

    def tool_catalog(invocation)
      invocation.tool_references.filter_map { |reference| catalog_entry(reference) }.join("\n\n")
    end

    def catalog_entry(reference)
      return if handoff_tool?(reference)

      tool = RecordingStudioAI.tools.fetch(reference.key, version: reference.version)
      return if tool.nil?

      [tool_heading(reference, tool), tool_guidance(tool), argument_line(tool), returns_line(tool)].compact.join("\n")
    end

    def handoff_tool?(reference)
      reference.key.to_s == Handoffs::INTERNAL_TOOL_KEY.to_s
    end

    def tool_heading(reference, tool)
      "#{reference.key} version #{reference.version}. #{tool.description}"
    end

    def tool_guidance(tool)
      "Use when: #{tool.use_when}\nDo not use when: #{tool.do_not_use_when}"
    end

    def returns_line(tool)
      "Returns: #{tool.returns}" unless tool.returns.empty?
    end

    def argument_line(tool)
      parameters = Array(tool.parameters)
      return "Arguments: none." if parameters.empty?

      "Arguments: #{parameters.map { |parameter| parameter_phrase(parameter) }.join('; ')}."
    end

    def parameter_phrase(parameter)
      requirement = parameter[:required] ? "required" : "optional"
      "#{parameter[:name]} (#{parameter[:type]}, #{requirement}): #{parameter[:description]}"
    end

    def lease_metadata(run, lease_token)
      {
        "agent_run_id" => run.id,
        "lease_token" => lease_token,
        # Recording Studio AI redacts metadata keys that contain "token"
        # before the tool runs. The digest still matches the live lease.
        "agent_lease_check" => Digest::SHA256.hexdigest(lease_token.to_s)
      }
    end

    def find_run(request_id:)
      return unless defined?(RecordingStudioAI::Run)

      RecordingStudioAI::Run.find_by(request_id: request_id)
    rescue StandardError
      nil
    end

    def retained_output(ai_run:, initiator:)
      retained = latest_retained_response(ai_run)
      return unless retained && initiator

      text, data = retained_text_and_data(retained, initiator)
      return if text.blank? && data.blank?

      { text: text, data: data }
    rescue StandardError
      nil
    end

    def latest_retained_response(ai_run)
      return unless ai_run.respond_to?(:attempts)

      attempt = Array(ai_run.attempts).max_by { |item| item.try(:sequence) || item.try(:id).to_i }
      attempt.response if attempt.respond_to?(:response)
    end
    private_class_method :latest_retained_response

    def retained_text_and_data(retained, initiator)
      payload = RecordingStudioAI.read_retained_response(response: retained, initiator: initiator)
      return [nil, nil] unless payload.is_a?(Hash)

      [payload[:content_text], payload[:normalized_response]]
    end
    private_class_method :retained_text_and_data

    def attribution_for(request)
      RecordingStudioAI::Contracts::Attribution.new(
        root_recording: request.root_recording,
        context_recording: request.context_recording,
        initiator: request.initiator,
        initiator_kind: request.initiator_kind,
        executor: request.executor,
        execution_source: request.execution_source
      )
    end
  end
end
