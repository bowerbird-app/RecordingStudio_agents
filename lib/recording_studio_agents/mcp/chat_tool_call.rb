# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # One in-process tool call: permission, API switch, rate limit, then dispatch.
    module ChatToolCall
      module_function

      def perform(name, arguments, actor:, root:, call_id:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        grant = ChatTools.installed? ? ChatTools.grant_for(actor, root) : nil
        result, limited = guarded(name, arguments, grant, actor, call_id)
        ChatToolLog.record(name, result, started, grant, limited)
        result
      end

      def outcome(result)
        text = result_text(result)
        return { error: bounded(text.presence || "tool call failed") } if error_result?(result)

        { output: bounded(text) }
      end

      def bounded(text)
        value = text.to_s
        limit = RecordingStudioAI::Agents::Request::MAX_TOOL_RESULT_BYTES
        return value if value.bytesize <= limit

        value.byteslice(0, limit).to_s.scrub("")
      end

      def guarded(name, arguments, grant, actor, call_id)
        refusal = refusal_for(name, grant)
        return [error_result(refusal), false] if refusal
        return [error_result("Too many requests"), true] if ChatToolLimit.limited?(grant, name, actor)

        [dispatch(name, arguments, grant, call_id), false]
      end

      def refusal_for(name, grant)
        return "tools are off" if ChatTools.off? || !ChatTools.installed?
        return "not allowed" if grant.nil? || ChatTools.self_tool?(name)
        return "tool is not allowed" unless allowed?(name, grant)
        return "API access is temporarily disabled" unless api_enabled?(grant)

        nil
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
