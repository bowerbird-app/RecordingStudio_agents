# frozen_string_literal: true

module RecordingStudioAgents
  module Digests
    module_function

    def of(value)
      Digest::SHA256.hexdigest(JSON.generate(normalize(value)))
    end

    def output_from(response)
      of(
        "text" => response.respond_to?(:text) ? response.text : nil,
        "data" => response.respond_to?(:structured_data) ? response.structured_data : nil
      )
    end

    def normalize(value)
      case value
      when Hash
        value.transform_keys(&:to_s).sort.to_h.transform_values { |item| normalize(item) }
      when Array
        value.map { |item| normalize(item) }
      when Symbol
        value.to_s
      else
        value
      end
    end
  end
end
