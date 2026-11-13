# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # A joined call stays out of the provider post. The first caller submits it.
    module PostedResults
      module_function

      def list(results)
        rows = Array(results)
        kept = rows.reject { |result| result.is_a?(Hash) && result[:joined] }
        return :quiet if rows.any? && kept.empty?

        kept
      end

      def quiet_turn
        Struct.new(:tool_calls).new([])
      end

      # Not assistant text. The first caller posts the tool result. This only
      # marks the round that joined and had nothing of its own to submit.
      def note(emit)
        emit&.call(Struct.new(:type, :text).new("already_handled", "already handled"))
        quiet_turn
      end

      def pending(source)
        return [] unless source.respond_to?(:tool_calls)

        Array(source.tool_calls)
      end
    end
  end
end
