# frozen_string_literal: true

module RecordingStudioAgents
  # One resolver for the signed-in person and the current workspace.
  # PopupsController and ChatkitController both use it.
  module RequestContext
    private

    def recording_studio_agents_resolve(name)
      resolver = RecordingStudioAgents.configuration.public_send(name)
      resolver.respond_to?(:call) ? resolver.call(self) : nil
    end
  end
end
