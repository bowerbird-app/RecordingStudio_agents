# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKitHelper
    def recording_studio_agents_chatkit(endpoint: nil)
      append_chatkit_views
      render partial: chatkit_partial, locals: chatkit_locals(endpoint)
    end

    private

    def append_chatkit_views
      root = Engine.root.join("app/views").to_s
      return if lookup_context.view_paths.map(&:to_s).include?(root)

      lookup_context.append_view_paths([root])
    end

    def chatkit_partial
      ChatKit::Readiness.configured? ? "recording_studio_agents/chatkit/frame" : "recording_studio_agents/chatkit/setup"
    end

    def chatkit_locals(endpoint)
      {
        endpoint: endpoint || recording_studio_agents.chatkit_path,
        missing: ChatKit::Readiness.missing,
        credential: ChatKit::Readiness.credential,
        credential_label: ChatKit::Readiness.credential_label
      }
    end
  end
end
