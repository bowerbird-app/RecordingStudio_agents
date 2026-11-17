# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # One Rails log line for a rescued ChatKit error.
    # The line is the site, the error class, a code when the error has one,
    # the message, and the request type when that type is a short token.
    # It never receives the request body, headers, cookies, or credentials.
    # JSON parse errors quote a piece of the source, so those quotes are left out.
    module ErrorLog
      PREFIX = "[recording_studio_agents.chatkit]"
      TYPE_KEY = :recording_studio_agents_chatkit_type
      TYPE_PATTERN = /\A[A-Za-z0-9_.-]+\z/
      SOURCE_QUOTE = /'(?:\\.|[^'])*'/

      module_function

      def call(error, site:, type: nil, level: :warn)
        logger = rails_logger
        return unless logger.respond_to?(level)

        logger.public_send(level, line(error, site: site, type: type))
        nil
      rescue StandardError
        nil
      end

      def with_type(type)
        previous = Thread.current[TYPE_KEY]
        Thread.current[TYPE_KEY] = type if usable_type?(type)
        yield
      ensure
        Thread.current[TYPE_KEY] = previous
      end

      def line(error, site:, type: nil)
        parts = [PREFIX, site.to_s, error.class.name]
        code = error_code(error)
        parts << "code=#{code}" if code
        message = message_for(error)
        parts << message unless message.empty?
        resolved = resolve_type(type)
        parts << "type=#{resolved}" if resolved
        parts.join(" ")
      end

      def resolve_type(type)
        return type if usable_type?(type)

        current = Thread.current[TYPE_KEY]
        current if usable_type?(current)
      end

      def usable_type?(type)
        type.is_a?(String) && !type.empty? && type.length <= 80 && type.match?(TYPE_PATTERN)
      end

      def error_code(error)
        return unless error.respond_to?(:code)

        code = error.code
        return if code.nil?
        return if code.respond_to?(:blank?) && code.blank?

        code
      end

      def message_for(error)
        text = error.message.to_s
        return text.gsub(SOURCE_QUOTE, "'...'") if error.is_a?(JSON::ParserError)

        text
      end

      def rails_logger
        return unless defined?(Rails) && Rails.respond_to?(:logger)

        Rails.logger
      end
    end
  end
end
