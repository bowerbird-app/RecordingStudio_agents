# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKitHelper
    def recording_studio_agents_chatkit(endpoint: nil, page_recording: nil, chatkit_options: nil)
      append_chatkit_views
      render partial: chatkit_partial, locals: chatkit_locals(endpoint, page_recording, chatkit_options)
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

    def chatkit_locals(endpoint, page_recording, chatkit_options)
      {
        endpoint: scoped_endpoint(endpoint, page_recording),
        chatkit_options: resolved_chatkit_options(chatkit_options),
        missing: ChatKit::Readiness.missing,
        credential: ChatKit::Readiness.credential,
        credential_label: ChatKit::Readiness.credential_label
      }
    end

    def resolved_chatkit_options(chatkit_options)
      return {} unless ChatKit::Readiness.configured?

      ChatKit::Options.for(controller, chatkit_options)
    end

    def scoped_endpoint(endpoint, page_recording)
      path = endpoint.presence || recording_studio_agents.chatkit_path
      return path if page_recording.nil?

      id = page_recording_id(page_recording)
      joiner = path.include?("?") ? "&" : "?"
      "#{path}#{joiner}#{ScopedParent::QUERY_PARAM}=#{ERB::Util.url_encode(id)}"
    end

    def page_recording_id(page_recording)
      raise ArgumentError, "page_recording must be a recording" unless page_recording.is_a?(RecordingStudio::Recording)

      page_recording.id
    end
  end
end
