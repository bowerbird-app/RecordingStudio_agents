# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    module Readiness
      # TypeSafe stays because Recording Studio AI v0.15.1 defines config.typesafe_api_key
      # in lib/recording_studio_ai/configuration.rb.
      PROVIDER_LABELS = { openai: "OpenAI", gemini: "Gemini", typesafe: "TypeSafe" }.freeze

      module_function

      def configured?
        missing.empty?
      end

      def missing
        [support_gap, credential_gap, domain_gap].compact
      end

      def credential
        return :provider_credential unless known_provider?

        :"#{hosted_provider}_api_key"
      end

      def credential_label
        return "Provider credential" unless known_provider?

        "#{PROVIDER_LABELS.fetch(hosted_provider)} API key"
      end

      def hosted_provider
        named = RecordingStudioAgents.configuration.provider
        return normalize_provider(named) if named.present?

        profile_hosted_provider || :openai
      end

      def support_gap
        :hosted_agent_unsupported unless hosted_agent?
      end

      def hosted_agent?
        profile_entries_for(hosted_provider).any? { |entry| hosted_model?(entry) }
      end

      def profile_entries_for(provider)
        profile_entries.select { |entry| normalize_provider(entry_value(entry, :provider)) == provider }
      end

      def profile_entries
        profile = RecordingStudioAgents.configuration.default_profile
        Array(RecordingStudioAI.configuration.profiles[profile])
      end

      def credential_gap
        return if support_gap
        return if provider_ready?(hosted_provider)

        credential
      end

      def domain_gap
        :domain_key if RecordingStudioAgents.configuration.chatkit_domain_key.blank?
      end

      def known_provider?
        PROVIDER_LABELS.key?(hosted_provider)
      end

      def provider_ready?(provider)
        adapter = RecordingStudioAI.configuration.providers[provider]
        return false if adapter.nil?
        return true unless adapter.respond_to?(:configured?)

        adapter.configured?
      end

      def profile_hosted_provider
        entry = profile_entries.find { |candidate| hosted_model?(candidate) }
        provider_from(entry)
      end

      def hosted_model?(entry)
        model = entry_value(entry, :model).to_s
        provider = normalize_provider(entry_value(entry, :provider))
        RecordingStudioAI.models.all.any? { |definition| hosted_definition?(definition, model, provider) }
      end

      def hosted_definition?(definition, model, provider)
        definition.model == model && definition.provider == provider && definition.operations.include?(:hosted_agent)
      end

      def provider_from(entry)
        value = entry_value(entry, :provider) if entry
        return if value.nil?

        normalize_provider(value)
      end

      def entry_value(entry, key)
        entry[key] || entry[key.to_s]
      end

      def normalize_provider(value)
        value.to_s.strip.downcase.to_sym
      end
    end
  end
end
