# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # One in-process tool call: permission, API switch, rate limit, then dispatch.
    module ChatToolCall
      module_function

      OFF = "tools are off"
      NOT_ALLOWED = "not allowed"
      TOOL_NOT_ALLOWED = "tool is not allowed"
      API_DISABLED = "API access is temporarily disabled"
      TOO_MANY = "Too many requests"
      FAILED = "tool call failed"
      OWNED_ERRORS = [OFF, NOT_ALLOWED, TOOL_NOT_ALLOWED, API_DISABLED, TOO_MANY, FAILED].freeze

      def perform(name, arguments, actor:, call_id:, turn_tools:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        row = ChatToolAudit.current_reserved || start_audit(name, arguments, actor, turn_tools, call_id)
        result, status = guarded(name, arguments, turn_tools, actor, call_id)
        ChatToolLog.record(name, result, started, turn_tools.grant, status == :limited)
        ChatToolAudit.finish!(row, status)
        result
      end

      def start_audit(name, arguments, actor, turn_tools, call_id)
        entry = ChatToolAudit::Entry.new(name: name, arguments: arguments, call_id: call_id)
        ChatToolAudit.begin!(entry, actor: actor, kind: turn_tools.kind_for(name))
      end

      def outcome(result)
        ChatToolOutput.pack(result_text(result), error_result?(result))
      end

      def bounded(text)
        ChatToolOutput.bounded(text)
      end

      def guarded(name, arguments, turn_tools, actor, call_id)
        refusal = refusal_for(name, turn_tools)
        return [error_result(refusal), :refused] if refusal
        return [error_result(TOO_MANY), :limited] if ChatToolLimit.limited?(turn_tools, name, actor)

        result = dispatch(name, arguments, turn_tools.grant, call_id)
        [result, error_result?(result) ? :error : :ok]
      end

      def refusal_for(name, turn_tools)
        return OFF if ChatTools.off? || !ChatTools.installed?
        return NOT_ALLOWED if turn_tools.grant.nil? || ChatTools.self_tool?(name)
        return TOOL_NOT_ALLOWED unless callable?(name, turn_tools)
        return API_DISABLED unless api_enabled?(turn_tools.grant)

        nil
      end

      def callable?(name, turn_tools)
        ChatTools.named_tool?(name) && allowed?(name, turn_tools)
      end

      def allowed?(name, turn_tools)
        return true if ChatTools.mode == :write

        turn_tools.read_only?(name)
      end

      def api_enabled?(grant)
        RecordingStudioApi::ApiSetting.api_access_enabled?(api: api_key(grant))
      rescue *store_errors => e
        log_call_error(e)
        false
      end

      def dispatch(name, arguments, grant, call_id)
        RecordingStudioMcp::Dispatcher.call(
          tool_name: name, arguments: arguments.is_a?(Hash) ? arguments : {},
          access_grant: grant, idempotency_key: call_id
        )
      rescue RecordingStudioApi::Error => e
        log_call_error(e)
        error_result(e.message.presence || "tool call failed")
      end

      def log_call_error(error)
        Rails.logger.error("[RecordingStudioAgents] #{error.class}: #{error.message}")
      end

      def store_errors
        [ActiveRecord::ActiveRecordError, "PG::Error".safe_constantize, "Redis::BaseError".safe_constantize].compact
      end

      def error_result?(result)
        result.is_a?(Hash) && (result[:isError] == true || result["isError"] == true)
      end

      def result_text(result)
        return "" unless result.is_a?(Hash)

        part = Array(result[:content] || result["content"]).first
        return "" unless part.is_a?(Hash)

        (part[:text] || part["text"]).to_s
      end

      def error_result(message)
        { content: [{ type: "text", text: message.to_s }], isError: true }
      end

      def api_key(grant)
        grant.api_client&.api_key.presence || "public"
      end
    end
  end
end
