# frozen_string_literal: true

# Reads host provider keys. The test suite stays offline so it never calls a model.
module DummyAIProviderKeys
  module_function

  def read(*environment_names, offline:)
    return if offline

    environment_names.each do |environment_name|
      secret = ENV[environment_name]
      return secret if secret.present?
    end

    nil
  end
end

RecordingStudioAI.configure do |config|
  offline = Rails.env.test?
  config.openai_api_key = DummyAIProviderKeys.read("OPENAI_API_KEY", offline: offline)
  # Google AI Studio supplies Gemini for generation. Cloud agents inject google_ai_studio.
  config.gemini_api_key = DummyAIProviderKeys.read(
    "GEMINI_API_KEY", "google_ai_studio", "GOOGLE_AI_STUDIO", offline: offline
  )
  # TypeSafe supplies Jev for decisions. Cloud agents inject typesafe.
  config.typesafe_api_key = DummyAIProviderKeys.read(
    "TYPESAFE_API_KEY", "typesafe", "TYPESAFE", offline: offline
  )

  config.default_profile = :medium
  # Generation resolves to Gemini. Decisions resolve to Jev. Each operation
  # keeps only the candidates that declare it.
  config.profiles = {
    low: [
      { provider: :gemini, model: "gemini-2.5-flash" },
      { provider: :typesafe, model: "jev-latest" }
    ],
    medium: [
      { provider: :gemini, model: "gemini-2.5-pro" },
      { provider: :typesafe, model: "jev-latest" }
    ],
    high: [
      { provider: :gemini, model: "gemini-2.5-pro" },
      { provider: :typesafe, model: "jev-latest" }
    ]
  }
  config.allowed_provider_overrides = %i[gemini typesafe]
  config.authorization_handler = RecordingStudioAI::AccessibleAuthorization.method(:call)
  config.custom_tool_confirmation_handler = lambda do |definition:, **|
    definition.requires_confirmation ? :pending : :approved
  end
end
