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
      def self.call(raw, actor:, root_recording:)
        new(actor, root_recording).call(raw)
      end

      def initialize(actor, root_recording)
        @actor = actor
        @root = root_recording
      end

      def call(raw)
        request = JSON.parse(raw)
        dispatch(request["type"].to_s, request.fetch("params", {}))
      rescue JSON::ParserError
        error("invalid request")
      rescue ProtocolError => e
        error(e.message, e.status)
      rescue IsolationError
        error("chat was not found", 404)
      rescue Error => e
        error(e.message, 403)
      end

      private

      def dispatch(type, params)
        params = {} unless params.is_a?(Hash)
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
        Result.stream(open_turn(nil, params))
      end

      def stream_existing(params)
        Result.stream(open_turn(catalog.find!(params["thread_id"]), params))
      end

      def open_turn(recording, params)
        Turn.open(
          actor: @actor, root: @root, text: Payload.user_text(params["input"]),
          recording: recording, idempotency_key: client_key(params)
        )
      end

      def client_key(params)
        metadata = params["metadata"]
        return unless metadata.is_a?(Hash)

        metadata["idempotency_key"].presence
      end

      def catalog
        @catalog ||= Catalog.new(@actor, @root)
      end

      def json(body)
        Result.json(body)
      end

      def error(message, status = 400)
        Result.json({ type: "error", code: "custom", message: message, allow_retry: false }, status)
      end
    end
  end
end
