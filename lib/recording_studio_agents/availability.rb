# frozen_string_literal: true

module RecordingStudioAgents
  # Site-wide on/off. Read on every call. A callable that raises is off.
  module Availability
    LOG_LINE = "[recording_studio_agents] enabled"

    module_function

    def enabled?(controller = nil)
      flag = RecordingStudioAgents.configuration.enabled
      return flag unless flag.respond_to?(:call)

      invoke(flag, controller) ? true : false
    rescue StandardError => e
      log_failure(e)
      false
    end

    def invoke(callable, controller)
      return callable.call if callable.arity.zero?

      callable.call(controller)
    end

    def log_failure(error)
      logger = rails_logger
      return unless logger.respond_to?(:warn)

      logger.warn("#{LOG_LINE} #{error.class}")
    rescue StandardError
      nil
    end

    def rails_logger
      return unless defined?(Rails) && Rails.respond_to?(:logger)

      Rails.logger
    end
    private_class_method :invoke, :log_failure, :rails_logger
  end
end
