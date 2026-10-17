# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    module Readiness
      module_function

      def configured?
        missing.empty?
      end

      def missing
        gaps = []
        gaps << :openai_api_key if RecordingStudioAI.configuration.openai_api_key.blank?
        gaps << :domain_key if RecordingStudioAgents.configuration.chatkit_domain_key.blank?
        gaps
      end
    end
  end
end
