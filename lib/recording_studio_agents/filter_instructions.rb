# frozen_string_literal: true

module RecordingStudioAgents
  module FilterInstructions
    # Exact parameter name. A bare :instructions would also hide shipping_instructions.
    PARAMETER = /\Ainstructions\z/

    module_function

    def apply(app)
      append(app.config.filter_parameters)
    end

    def append(list)
      return if listed?(list)

      list << PARAMETER
    end

    def listed?(list)
      list.any? { |entry| entry.is_a?(Regexp) && entry.source == PARAMETER.source }
    end
  end
end
