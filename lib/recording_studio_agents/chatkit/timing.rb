# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # One info line per ChatKit phase. The line is the phase, a duration,
    # the queries in that phase, and the request type. A tool line adds the
    # tool name. A round line adds the round number. It never receives message
    # text, tool arguments, tool results, page context, tokens, headers, or
    # credentials.
    module Timing
      KEY = :recording_studio_agents_chatkit_timing
      TEXT_DELTA = "assistant_message.content_part.text_delta"
      PHASE = /\A[a-z_]+\z/
      TOOL_NAME = /\A[A-Za-z0-9_-]{1,64}\z/
      COUNTS = %w[n q db tools answers_ms model_ms dropped].freeze
      Stamp = Struct.new(:at, :queries, :db)
      LISTEN = Mutex.new

      module_function

      def open(type: nil)
        QueryTiming.listen
        Thread.current[KEY] = {
          started: clock, type: usable_type(type), ttft: false, queries: 0, db_ms: 0.0, dropped: 0
        }
        nil
      end

      def note_type(type)
        state = current
        return unless state

        state[:type] ||= usable_type(type)
        nil
      end

      def note_drop
        state = current
        return unless state

        state[:dropped] = state[:dropped].to_i + 1
        nil
      end

      def measure(phase, **extra)
        return yield unless current

        stamp = mark
        yield
      ensure
        write(phase, elapsed_ms(stamp), QueryTiming.delta(stamp).merge(extra)) if stamp
      end

      def mark
        sample = QueryTiming.sample
        Stamp.new(clock, sample[:q], sample[:db])
      end

      def round(number, started, **extra)
        return unless current && started

        fields = started.is_a?(Stamp) ? QueryTiming.delta(started) : {}
        write("round", elapsed_ms(started), fields.merge(n: number, **extra))
      end

      def wrote(json)
        state = current
        return unless state
        return if state[:ttft]
        return unless text_delta?(json)

        state[:ttft] = true
        write("ttft", elapsed_ms(state[:started]), QueryTiming.totals(state))
      end

      def finish
        state = current
        write("total", elapsed_ms(state[:started]), QueryTiming.total_fields(state)) if state
        nil
      ensure
        Thread.current[KEY] = nil
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started)
        return unless started

        at = started.is_a?(Stamp) ? started.at : started
        ((clock - at) * 1000).round
      end

      def write(phase, milliseconds, extra)
        return unless phase.to_s.match?(PHASE)
        return unless milliseconds

        logger = rails_logger
        return unless logger.respond_to?(:info)

        logger.info(line(phase, milliseconds, extra))
      rescue StandardError
        nil
      end

      def line(phase, milliseconds, extra)
        TimingLine.compose(phase, milliseconds, extra, current)
      end

      def text_delta?(json)
        data = JSON.parse(json.to_s)
        data.is_a?(Hash) && data.dig("update", "type") == TEXT_DELTA
      rescue JSON::ParserError
        false
      end

      def usable_type(type)
        type if ErrorLog.usable_type?(type)
      end

      def current
        Thread.current[KEY]
      end

      def rails_logger
        return unless defined?(Rails) && Rails.respond_to?(:logger)

        Rails.logger
      end
    end

    module TimingLine
      module_function

      def compose(phase, milliseconds, extra, state)
        parts = [ErrorLog::PREFIX, "timing", "phase=#{phase}"]
        Array(extra).each { |key, value| parts << piece(key, value) }
        parts << "ms=#{milliseconds}"
        parts << "type=#{state[:type]}" if state && state[:type]
        parts.compact.join(" ")
      end

      def piece(key, value)
        return if value.nil?

        label = key.to_s
        return "name=#{tool_name(value)}" if label == "name"
        return unless Timing::COUNTS.include?(label)

        "#{label}=#{value.to_i}"
      end

      def tool_name(value)
        text = value.to_s
        text.match?(Timing::TOOL_NAME) ? text : "unknown"
      end
    end

    # SQL counts for the timing lines. One process-wide subscriber.
    # It records on the current thread only while a ChatKit timing block is open.
    module QueryTiming
      module_function

      def listen
        return if @listening

        Timing::LISTEN.synchronize do
          next if @listening
          next unless defined?(ActiveSupport::Notifications)

          ActiveSupport::Notifications.subscribe("sql.active_record") { |*args| note(*args) }
          @listening = true
        end
      end

      def note(*args)
        state = Timing.current
        return unless state

        payload, duration = sql_payload(args)
        return if payload.nil? || payload[:cached] || payload[:name] == "SCHEMA"

        state[:queries] += 1
        state[:db_ms] += duration.to_f
      end

      def sample
        state = Timing.current
        return { q: 0, db: 0.0 } unless state

        { q: state[:queries], db: state[:db_ms] }
      end

      def delta(stamp)
        now = sample
        { q: now[:q] - stamp.queries, db: (now[:db] - stamp.db).round }
      end

      def totals(state)
        { q: state[:queries], db: state[:db_ms].round }
      end

      def total_fields(state)
        fields = totals(state)
        fields[:dropped] = state[:dropped] if state[:dropped].to_i.positive?
        fields
      end

      def sql_payload(args)
        event = args.first
        return [event.payload, event.duration] if args.length == 1 && event.respond_to?(:payload)
        return unless args.length >= 5

        [args[4], (args[2] - args[1]) * 1000.0]
      end
    end
  end
end
