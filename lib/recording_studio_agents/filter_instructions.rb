# frozen_string_literal: true

module RecordingStudioAgents
  module FilterInstructions
    module_function

    def apply(app)
      append(app.config.filter_parameters)
      append_attributes
    end

    def append(list)
      return if listed?(list)

      list << :instructions
    end

    def listed?(list)
      list.any? { |entry| entry.to_s == "instructions" }
    end

    def append_attributes
      return unless defined?(ActiveRecord::Base)

      attributes = ActiveRecord::Base.filter_attributes
      return if listed?(attributes)

      ActiveRecord::Base.filter_attributes += [:instructions]
    end
  end
end
