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

      # No event. ChatKit only renders known stream events, and none means "already handled".
      # The stream ends here. The first caller posts the real result.
      def quiet_turn
        Struct.new(:tool_calls).new([])
      end

      def settled_rejection?(error)
        text = error.message.to_s
        text.include?("already submitted") || text.include?("unknown tool result call_id")
      end

      def end_if_settled(error)
        raise error unless settled_rejection?(error)

        quiet_turn
      end

      def pending(source)
        return [] unless source.respond_to?(:tool_calls)

        Array(source.tool_calls)
      end
    end
  end
end
