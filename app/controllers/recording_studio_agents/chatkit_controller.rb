# frozen_string_literal: true

module RecordingStudioAgents
  class ChatkitController < ApplicationController
    include ActionController::Live
    include RequestContext

    layout false

    def create
      actor = recording_studio_agents_resolve(:request_actor)
      return signed_out if actor.blank?

      root = recording_studio_agents_resolve(:request_root)
      return signed_out if root.blank?

      ChatKit::Timing.open(type: chatkit_request_type)
      serve(actor, root)
    ensure
      ChatKit::Timing.finish
    end

    private

    def serve(actor, root)
      ChatKit::UsageNotice.context(request: request, root_recording: root) do
        ChatKit::ErrorLog.with_type(chatkit_request_type) { render_result chat_result(actor, root) }
      rescue RecordingStudioAI::Errors::UsageDeclined => e
        render_declined(e)
      end
    rescue ChatKit::ProtocolError, RecordingStudioAI::Errors::ContractValidationError => e
      render_rejected(e)
    end

    def render_declined(error)
      ChatKit::ErrorLog.call(error, site: "chatkit_controller.create", type: chatkit_request_type)
      declined = ChatKit::UsageNotice.result(request.raw_post)
      declined ? render_result(declined) : render_error(error.message, 400)
    end

    def render_rejected(error)
      ChatKit::ErrorLog.call(error, site: "chatkit_controller.create", type: chatkit_request_type)
      render_error(error.message, response_status(error))
    end

    def chat_result(actor, root)
      ChatKit::Server.call(
        request.raw_post,
        actor: actor,
        root_recording: root,
        page_recording: page_recording(root, actor),
        page_context: ChatKit::PageContext.parse(request.headers[ChatKit::PageContext::HEADER])
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
      result.each { |json| write_event(json) }
    rescue IOError, ActionController::Live::ClientDisconnected => e
      ChatKit::ErrorLog.call(e, site: "chatkit_controller.stream_result", level: :info)
      result.cancel!
    ensure
      response.stream.close
    end

    def write_event(json)
      response.stream.write("data: #{json}\n\n")
      ChatKit::Timing.wrote(json)
    end

    def sse_headers
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["X-Accel-Buffering"] = "no"
    end

    def signed_out
      render_error("sign in is required", 401)
    end

    def render_error(message, status)
      render json: { type: "error", code: "custom", message: message, allow_retry: false }, status: status
    end

    def response_status(error)
      return error.status if error.is_a?(ChatKit::ProtocolError)

      error.code.to_s == "authorization" ? 403 : 400
    end

    # The ChatKit operation name only. A missing or odd type is left off the log line.
    def chatkit_request_type
      data = JSON.parse(request.raw_post.to_s)
      return unless data.is_a?(Hash)

      type = data["type"]
      type if type.is_a?(String)
    rescue StandardError
      nil
    end
  end
end
