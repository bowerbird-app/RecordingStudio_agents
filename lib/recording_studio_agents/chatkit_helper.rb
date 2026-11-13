# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKitHelper
    # Sign in uses target=_top, so the framed page needs that sandbox token.
    POPUP_IFRAME_SANDBOX = %w[
      allow-scripts
      allow-same-origin
      allow-forms
      allow-popups
      allow-top-navigation-by-user-activation
    ].join(" ").freeze

    # FlatPack assigns a random id unless one is passed. Turbo Drive matches
    # data-turbo-permanent by that id, so a visit would drop the iframe and
    # the open state. This id stays the same on every page that renders the launcher.
    LAUNCHER_ELEMENT_ID = "recording_studio_agents_launcher"

    def recording_studio_agents_launcher(label: "Open chat", title: "Chat", position: :bottom_left)
      return unless RecordingStudioAgents.configuration.launcher

      frame = render FlatPack::FloatingFrame::Component.new(
        src: engine_route(:popup_path), title: title, label: label, icon: :chat,
        position: position, padding: :none, sandbox: POPUP_IFRAME_SANDBOX, allow: "clipboard-write",
        id: LAUNCHER_ELEMENT_ID, data: { turbo_permanent: true }
      )
      safe_join([frame, launcher_scripts])
    end

    def recording_studio_agents_chatkit(endpoint: nil, page_recording: nil, chatkit_options: nil, fill: false)
      append_chatkit_views
      render partial: chatkit_partial, locals: chatkit_locals(endpoint, page_recording, chatkit_options, fill)
    end

    private

    def launcher_scripts
      names = %w[recording_studio_agents/page_context recording_studio_agents/launcher]
      safe_join(names.map { |name| javascript_include_tag(name, "data-turbo-track": "reload") })
    end

    def append_chatkit_views
      root = Engine.root.join("app/views").to_s
      return if lookup_context.view_paths.map(&:to_s).include?(root)

      lookup_context.append_view_paths([root])
    end

    def chatkit_partial
      ChatKit::Readiness.configured? ? "recording_studio_agents/chatkit/frame" : "recording_studio_agents/chatkit/setup"
    end

    def chatkit_locals(endpoint, page_recording, chatkit_options, fill)
      {
        endpoint: scoped_endpoint(endpoint, page_recording),
        chatkit_options: resolved_chatkit_options(chatkit_options),
        missing: ChatKit::Readiness.missing,
        credential: ChatKit::Readiness.credential,
        credential_label: ChatKit::Readiness.credential_label,
        fill: fill
      }
    end

    def resolved_chatkit_options(chatkit_options)
      return {} unless ChatKit::Readiness.configured?

      ChatKit::Options.for(controller, chatkit_options)
    end

    def scoped_endpoint(endpoint, page_recording)
      path = endpoint.presence || engine_route(:chatkit_path)
      return path if page_recording.nil?

      id = page_recording_id(page_recording)
      joiner = path.include?("?") ? "&" : "?"
      "#{path}#{joiner}#{ScopedParent::QUERY_PARAM}=#{ERB::Util.url_encode(id)}"
    end

    def engine_route(name)
      RecordingStudioAgents::Engine.routes.url_helpers.public_send(name)
    end

    def page_recording_id(page_recording)
      raise ArgumentError, "page_recording must be a recording" unless page_recording.is_a?(RecordingStudio::Recording)

      page_recording.id
    end
  end
end
