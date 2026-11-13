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

      def perform(name, arguments, actor:, root:, call_id:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        grant = ChatTools.installed? ? ChatTools.grant_for(actor, root) : nil
        result, status = guarded(name, arguments, grant, actor, call_id)
        ChatToolLog.record(name, result, started, grant, status == :limited)
        entry = ChatToolAudit::Entry.new(name: name, arguments: arguments, call_id: call_id)
        ChatToolAudit.record!(entry, actor: actor, kind: ChatTools.kind_for(name, grant), outcome: status.to_s)
        result
      end

      def outcome(result)
        ChatToolOutput.pack(result_text(result), error_result?(result))
      end

      def bounded(text)
        ChatToolOutput.bounded(text)
      end

      def guarded(name, arguments, grant, actor, call_id)
        refusal = refusal_for(name, grant)
        return [error_result(refusal), :refused] if refusal
        return [error_result(TOO_MANY), :limited] if ChatToolLimit.limited?(grant, name, actor)

        result = dispatch(name, arguments, grant, call_id)
        [result, error_result?(result) ? :error : :ok]
      end

      def refusal_for(name, grant)
        return OFF if ChatTools.off? || !ChatTools.installed?
        return NOT_ALLOWED if grant.nil? || ChatTools.self_tool?(name)
        return TOOL_NOT_ALLOWED unless callable?(name, grant)
        return API_DISABLED unless api_enabled?(grant)

        nil
      end

      def callable?(name, grant)
        ChatTools.named_tool?(name) && allowed?(name, grant)
      end

      def allowed?(name, grant)
        return true if ChatTools.mode == :write

        RecordingStudioMcp::ToolSurface.for(access_grant: grant).read_only_tool?(name)
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
