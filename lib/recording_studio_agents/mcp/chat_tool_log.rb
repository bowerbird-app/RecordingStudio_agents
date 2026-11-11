# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # Counts a chat tool call in the MCP usage log. The tool output stays out of that row.
    module ChatToolLog
      module_function

      def record(name, result, started, grant, limited)
        return unless defined?(RecordingStudioMcp::UsageRecorder)

        RecordingStudioMcp::UsageRecorder.record!(usage_call(name, result, started, grant, limited))
      end

      def usage_call(name, result, started, grant, limited)
        failed = limited || ChatToolCall.error_result?(result)
        RecordingStudioMcp::UsageCall.new(
          request_payload: { "method" => "tools/call", "params" => { "name" => name.to_s } },
          response_body: { "result" => { "isError" => failed } },
          status: limited ? 429 : 200,
          duration_ms: elapsed_ms(started),
          rate_limited: limited,
          api_client_id: grant&.api_client&.id
        )
      end

      def elapsed_ms(started)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      end
    end
  end
end
