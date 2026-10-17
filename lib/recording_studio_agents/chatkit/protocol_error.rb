# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    class ProtocolError < Error
      attr_reader :status

      def initialize(message, status: 400)
        super(message)
        @status = status
      end
    end
  end
end
