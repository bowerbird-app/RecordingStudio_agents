# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # One info line per ChatKit phase. The line is the phase, a duration,
    # and the request type. A tool line adds the tool name. A round line
    # adds the round number. It never receives message text, tool arguments,
    # tool results, page context, tokens, headers, or credentials.
    module Timing
      KEY = :recording_studio_agents_chatkit_timing
      TEXT_DELTA = "assistant_message.content_part.text_delta"
      PHASE = /\A[a-z_]+\z/
      TOOL_NAME = /\A[A-Za-z0-9_-]{1,64}\z/

      module_function

      def open(type: nil)
        Thread.current[KEY] = { started: clock, type: usable_type(type), ttft: false }
        nil
      end

      def note_type(type)
        state = current
        return unless state

        state[:type] ||= usable_type(type)
        nil
      end

      def measure(phase, **extra)
        started = clock
        yield
      ensure
        write(phase, elapsed_ms(started), extra) if started
      end

      def mark
        clock
      end

      def round(number, started)
        write("round", elapsed_ms(started), { n: number })
      end

      def wrote(json)
        state = current
        return unless state
        return if state[:ttft]
        return unless text_delta?(json)

        state[:ttft] = true
        write("ttft", elapsed_ms(state[:started]), {})
      end

      def finish
        state = current
        write("total", elapsed_ms(state[:started]), {}) if state
        nil
      ensure
        Thread.current[KEY] = nil
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started)
        return unless started

        ((clock - started) * 1000).round
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
        parts = [ErrorLog::PREFIX, "timing", "phase=#{phase}"]
        Array(extra).each { |key, value| parts << piece(key, value) }
        parts << "ms=#{milliseconds}"
        parts << "type=#{current[:type]}" if current && current[:type]
        parts.compact.join(" ")
      end

      def piece(key, value)
        case key.to_s
        when "name" then "name=#{tool_name(value)}"
        when "n" then "n=#{value.to_i}"
        end
      end

      def tool_name(value)
        text = value.to_s
        text.match?(TOOL_NAME) ? text : "unknown"
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
  end
end
