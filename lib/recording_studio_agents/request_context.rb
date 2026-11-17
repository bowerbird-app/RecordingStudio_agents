# frozen_string_literal: true

module RecordingStudioAgents
  # One resolver for the signed-in person and the current workspace.
  # PopupsController, ChatkitController, and the launcher helper use it.
  module RequestContext
    module_function

    def recording_studio_agents_resolve(name, controller = self)
      resolver = RecordingStudioAgents.configuration.public_send(name)
      resolver.respond_to?(:call) ? resolver.call(controller) : nil
    end
  end
end
