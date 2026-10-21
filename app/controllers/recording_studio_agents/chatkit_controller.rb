# frozen_string_literal: true

module RecordingStudioAgents
  class ChatkitController < ApplicationController
    include ActionController::Live

    def create
      actor = resolve(:request_actor)
      root = resolve(:request_root)
      return render_error("sign in is required", 401) if actor.blank? || root.blank?

      page = ScopedParent.resolve!(params[ScopedParent::QUERY_PARAM], root: root, actor: actor)
      result = ChatKit::Server.call(request.raw_post, actor: actor, root_recording: root, page_recording: page)
      result.streaming? ? stream_result(result) : render(json: result.body, status: result.status)
    rescue ChatKit::ProtocolError => e
      render_error(e.message, e.status)
    end

    private

    def stream_result(result)
      sse_headers
      result.each { |json| response.stream.write("data: #{json}\n\n") }
    rescue IOError, ActionController::Live::ClientDisconnected
      result.cancel!
    ensure
      response.stream.close
    end

    def sse_headers
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["X-Accel-Buffering"] = "no"
    end

    def resolve(name)
      resolver = RecordingStudioAgents.configuration.public_send(name)
      resolver.respond_to?(:call) ? resolver.call(self) : nil
    end

    def render_error(message, status)
      render json: { type: "error", code: "custom", message: message, allow_retry: false }, status: status
    end
  end
end
