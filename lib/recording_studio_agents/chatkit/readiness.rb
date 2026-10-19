# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    module Readiness
      PROVIDER_LABELS = { openai: "OpenAI", gemini: "Gemini", typesafe: "TypeSafe" }.freeze

      module_function

      def configured?
        missing.empty?
      end

      def missing
        [credential_gap, domain_gap].compact
      end

      def credential
        :"#{hosted_provider}_api_key"
      end

      def credential_label
        "#{provider_label} API key"
      end

      def hosted_provider
        named = RecordingStudioAgents.configuration.provider
        return named.to_s.downcase.to_sym if named.present?

        profile_hosted_provider || :openai
      end

      def credential_gap
        provider = hosted_provider
        return if provider_ready?(provider)

        :"#{provider}_api_key"
      end

      def domain_gap
        :domain_key if RecordingStudioAgents.configuration.chatkit_domain_key.blank?
      end

      def provider_ready?(provider)
        adapter = RecordingStudioAI.configuration.providers[provider]
        return false if adapter.nil?
        return true unless adapter.respond_to?(:configured?)

        adapter.configured?
      end

      def profile_hosted_provider
        profile = RecordingStudioAgents.configuration.default_profile
        entries = Array(RecordingStudioAI.configuration.profiles[profile])
        entry = entries.find { |candidate| hosted_model?(candidate) }
        provider_from(entry)
      end

      def hosted_model?(entry)
        model = entry_value(entry, :model).to_s
        provider = entry_value(entry, :provider).to_s.downcase.to_sym
        RecordingStudioAI.models.all.any? { |definition| hosted_definition?(definition, model, provider) }
      end

      def hosted_definition?(definition, model, provider)
        definition.model == model && definition.provider == provider && definition.operations.include?(:hosted_agent)
      end

      def provider_from(entry)
        value = entry_value(entry, :provider) if entry
        return if value.nil?

        value.to_s.downcase.to_sym
      end

      def entry_value(entry, key)
        entry[key] || entry[key.to_s]
      end

      def provider_label
        PROVIDER_LABELS.fetch(hosted_provider) { hosted_provider.to_s.tr("_", " ").split.map(&:capitalize).join(" ") }
      end
    end
  end
end
