# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # The chat tool audit is exhaust. Recording Studio Logs keeps it indefinite and unsummarized.
    module LogsRegistration
      SOURCE_MODEL = "RecordingStudioAgents::ChatToolAudit"
      OWNER = "RecordingStudioAgents"

      module_function

      def register!
        return unless defined?(RecordingStudioLogs)

        RecordingStudioLogs.register(
          model: SOURCE_MODEL,
          timestamp_column: :occurred_at,
          partition_interval: nil,
          owner: OWNER,
          retention: :indefinite
        )
      end
    end
  end
end
