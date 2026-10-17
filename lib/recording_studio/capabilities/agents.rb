# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module Agents
      def self.to(**)
        RecordingStudio::Capabilities.include_for(:agents, **)
      end

      module RecordingMethods
        def agent_chats
          RecordingStudio::Recording.unscoped.where(
            parent_recording_id: id,
            recordable_type: "RecordingStudioAgents::Session"
          )
        end
      end
    end
  end
end

RecordingStudio.register_capability(
  :agents,
  recording_methods: RecordingStudio::Capabilities::Agents::RecordingMethods,
  source: "recording_studio_agents",
  child_recordables: ["RecordingStudioAgents::Session"]
)
