# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    class Result
      attr_reader :body, :status, :turn

      def self.json(body, status = 200)
        new(body, status, nil)
      end

      def self.stream(turn)
        new(nil, 200, turn)
      end

      def initialize(body, status, turn)
        @body = body
        @status = status
        @turn = turn
      end

      def streaming?
        !@turn.nil?
      end

      def each(&)
        @turn.each(&)
      end

      def cancel!
        @turn&.cancel!
      end
    end

    class Server
      def self.call(raw, actor:, root_recording:, page_recording: nil, page_context: nil)
        new(actor, root_recording, page_recording: page_recording, page_context: page_context).call(raw)
      end

      def initialize(actor, root_recording, page_recording: nil, page_context: nil)
        @actor = actor
        @root = root_recording
        @page_recording = page_recording
        @page_context = page_context || PageContext.parse(nil)
      end

      def call(raw)
        request = JSON.parse(raw)
        type = request["type"].to_s
        @request_type = type
        Timing.note_type(type)
        ErrorLog.with_type(type) { dispatch(type, request.fetch("params", {})) }
      rescue JSON::ParserError, Error => e
        fail_request(e)
      end

      private

      def dispatch(type, params)
        params = {} unless params.is_a?(Hash)
        reject_client_instructions!(params)
        streaming(type, params) || catalog_result(type, params) || error("unsupported operation")
      end

      def streaming(type, params)
        case type
        when "threads.create" then stream_new(params)
        when "threads.add_user_message" then stream_existing(params)
        end
      end

      def catalog_result(type, params)
        case type
        when "threads.get_by_id" then json(catalog.show_thread(params))
        when "threads.list" then json(catalog.list_threads(params))
        when "threads.update" then json(catalog.update_thread(params))
        when "threads.delete" then json(catalog.delete_thread(params))
        when "items.list" then json(catalog.list_items(params))
        end
      end

      def stream_new(params)
        Result.stream(open_turn(Payload.user_text(params["input"])))
      end

      def open_turn(text)
        Turn.open(
          actor: @actor, root: @root, text: text, page_context: @page_context,
          page_recording: @page_recording, request_type: @request_type
        )
      end

      def reject_client_instructions!(params)
        return if params["instructions"].nil?

        raise ProtocolError, "ChatKit does not accept instructions"
      end

      def stream_existing(params)
        recording = catalog.find!(params["thread_id"])
        Result.stream(continue(recording, params))
      end

      def continue(recording, params)
        Turn.follow(
          actor: @actor, root: @root, text: Payload.user_text(params["input"]),
          recording: recording, page_context: @page_context, request_type: @request_type
        )
      end

      def catalog
        @catalog ||= Catalog.new(@actor, @root, page_recording: @page_recording)
      end

      def json(body)
        Result.json(body)
      end

      def fail_request(caught)
        ErrorLog.call(caught, site: "server.call", type: @request_type)
        case caught
        when JSON::ParserError then error("invalid request")
        when ProtocolError then error(caught.message, caught.status)
        when IsolationError then error("chat was not found", 404)
        else error(caught.message, 403)
        end
      end

      def error(message, status = 400)
        Result.json({ type: "error", code: "custom", message: message, allow_retry: false }, status)
      end
    end
  end
end
