# frozen_string_literal: true

module RecordingStudioAgents
  class ChatkitController < ApplicationController
    include ActionController::Live

    layout false

    def create
      actor = resolve(:request_actor)
      return signed_out if actor.blank?

      root = resolve(:request_root)
      return signed_out if root.blank?

      render_result chat_result(actor, root)
    rescue ChatKit::ProtocolError => e
      render_error(e.message, e.status)
    rescue RecordingStudioAI::Errors::ContractValidationError => e
      render_error(e.message, e.code.to_s == "authorization" ? 403 : 400)
    end

    private

    def chat_result(actor, root)
      ChatKit::Server.call(
        request.raw_post,
        actor: actor,
        root_recording: root,
        page_recording: page_recording(root, actor)
      )
    end

    def page_recording(root, actor)
      ScopedParent.resolve!(params[ScopedParent::QUERY_PARAM], root: root, actor: actor)
    end

    def render_result(result)
      result.streaming? ? stream_result(result) : render(json: result.body, status: result.status)
    end

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

    def signed_out
      render_error("sign in is required", 401)
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
