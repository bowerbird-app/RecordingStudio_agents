# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # http(s) URLs and host paths for the out-of-credits link. Other schemes are rejected.
    module CreditUrl
      MESSAGE = "out_of_credits_url must be an http(s) URL or a path"

      module_function

      def parse!(value)
        href = parse(value)
        raise Error, MESSAGE if href.nil?

        href
      end

      def parse(value)
        raw = value.is_a?(String) ? value.strip : nil
        return if raw.nil? || raw.empty? || raw.match?(/[[:space:]\\]/)
        return if unsafe_scheme?(raw)
        return relative(raw) if raw.start_with?("/")

        http(raw)
      end

      # ChatKit's frame origin is the ChatKit host, not this app. A path is joined
      # to the request origin so the link resolves on the host. ChatKit opens
      # http(s) markdown links with target="_blank". The widget has no target="_top".
      def on_host(href, request)
        return href if href.match?(/\Ahttps?:/i)

        base = request.respond_to?(:base_url) ? request.base_url.to_s.delete_suffix("/") : ""
        return href if base.empty?

        "#{base}#{href}"
      end

      def unsafe_scheme?(raw)
        raw.match?(/\A[a-z][a-z0-9+.-]*:/i) && !raw.match?(/\Ahttps?:/i)
      end

      def relative(raw)
        return if raw.start_with?("//") || raw.include?("..")

        raw
      end

      def http(raw)
        uri = URI.parse(raw)
        return unless uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme) && uri.host.present?

        raw
      rescue URI::InvalidURIError
        nil
      end
    end

    # A declined send is shown in the open stream and is not stored.
    class UsageNotice
      CONTEXT = :recording_studio_agents_usage_notice
      TYPES = %w[threads.create threads.add_user_message].freeze
      MESSAGE_KEY = "recording_studio_agents.chat.out_of_credits.message"
      ACTION_KEY = "recording_studio_agents.chat.out_of_credits.action"

      def self.context(request:, root_recording:)
        previous = Thread.current[CONTEXT]
        Thread.current[CONTEXT] = { request: request, root_recording: root_recording }
        yield
      ensure
        Thread.current[CONTEXT] = previous
      end

      def self.result(raw)
        body = JSON.parse(raw.to_s)
        return unless body.is_a?(Hash) && TYPES.include?(body["type"].to_s)

        params = body["params"].is_a?(Hash) ? body["params"] : {}
        Result.stream(Live.new(type: body["type"].to_s, params: params))
      rescue JSON::ParserError, ProtocolError
        nil
      end

      def self.event(thread_id:)
        { type: "thread.item.done", item: assistant_item(thread_id, copy) }
      end

      def self.copy
        message = I18n.t(MESSAGE_KEY)
        href = RecordingStudioAgents.configuration.out_of_credits_href(**bound)
        return message if href.nil? || href.empty?

        "#{message}\n\n[#{markdown_label(action_label)}](#{href})"
      end

      def self.bound
        current = Thread.current[CONTEXT] || {}
        { request: current[:request], root_recording: current[:root_recording] }
      end

      def self.action_label
        text = RecordingStudioAgents.configuration.out_of_credits_label
        return text if text.is_a?(String) && !text.strip.empty?

        I18n.t(ACTION_KEY)
      end

      def self.markdown_label(text)
        text.to_s.gsub(/[\\\[\]]/) { |char| "\\#{char}" }
      end

      def self.assistant_item(thread_id, text)
        Payload.assistant_message(
          id: SecureRandom.uuid, thread_id: thread_id, text: text, created_at: Time.current
        )
      end

      # Live events for a decline that happened before the turn was stored.
      class Live
        def initialize(type:, params:)
          @created = type == "threads.create"
          @text = Payload.user_text(params["input"])
          @thread_id = thread_id_for(params)
          @time = Time.current
          @copy = UsageNotice.copy
          @user_id = SecureRandom.uuid
          @notice_id = SecureRandom.uuid
        end

        def each
          return enum_for(:each) unless block_given?

          events.each { |event| yield JSON.generate(event) }
        end

        def cancel! = nil

        # A new chat has no recording. This id exists only in the live stream.
        # It is a UUID that is not a recording id, so threads.get_by_id is 404.
        # A refresh reads threads.list and does not show the declined turn.
        def self.transient_id
          SecureRandom.uuid
        end

        private

        def thread_id_for(params)
          return self.class.transient_id if @created

          params["thread_id"].to_s.then { |id| id.empty? ? self.class.transient_id : id }
        end

        def events
          list = []
          list << thread_event if @created
          list << user_event
          list << notice_event
          list
        end

        def thread_event
          recordable = Struct.new(:title, :status).new(@text.truncate(60), "active")
          recording = Struct.new(:id, :recordable, :created_at).new(@thread_id, recordable, @time)
          { type: "thread.created", thread: Payload.thread(recording, items: { data: [], has_more: false }) }
        end

        def user_event
          item = Struct.new(:id, :text, :created_at).new(@user_id, @text, @time)
          { type: "thread.item.done", item: Payload.user_message(item, @thread_id) }
        end

        def notice_event
          item = Payload.assistant_message(id: @notice_id, thread_id: @thread_id, text: @copy, created_at: @time)
          { type: "thread.item.done", item: item }
        end
      end
    end
  end
end
