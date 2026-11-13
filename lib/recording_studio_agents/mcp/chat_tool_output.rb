# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # Tool text sent back to the model. Our own refusals stay plain sentences.
    module ChatToolOutput
      module_function

      def pack(text, failed)
        return { error: error_text(text) } if failed

        { output: envelope(text) }
      end

      def error_text(text)
        message = text.presence || ChatToolCall::FAILED
        return bounded(message) if ChatToolCall::OWNED_ERRORS.include?(message)

        envelope(message)
      end

      def envelope(text)
        body = text.to_s.scrub("")
        json = JSON.generate("untrusted_tool_output" => body)
        return json if json.bytesize <= result_limit

        fitted(body, result_limit)
      end

      def fitted(text, limit)
        best = JSON.generate("untrusted_tool_output" => "")
        low = 0
        high = text.bytesize
        low, high, best = step(text, limit, low, high, best) while low <= high
        best
      end

      def step(text, limit, low, high, best)
        mid = (low + high) / 2
        json = JSON.generate("untrusted_tool_output" => text.byteslice(0, mid).to_s.scrub(""))
        return [mid + 1, high, json] if json.bytesize <= limit

        [low, mid - 1, best]
      end

      def bounded(text)
        value = text.to_s
        return value if value.bytesize <= result_limit

        value.byteslice(0, result_limit).to_s.scrub("")
      end

      def result_limit
        RecordingStudioAI::Agents::Request::MAX_TOOL_RESULT_BYTES
      end
    end
  end
end
