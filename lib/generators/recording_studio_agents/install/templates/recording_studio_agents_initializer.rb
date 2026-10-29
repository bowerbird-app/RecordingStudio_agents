# frozen_string_literal: true

RecordingStudioAgents.configure do |config|
  # config.instructions = "Answer in plain language."
  # Nobody may pass a per-chat override until this is :admin or :edit. There is no replace mode.
  # config.instructions_override = :none
  # config.max_instructions_length = 4000
  # config.default_profile = :medium
  # config.purpose = "agent_chat"
  # config.provider = "openai"
  # Passed on a new chat only when Recording Studio AI allowed_provider_overrides includes it.
  # config.retention_period = 30.days
  # config.chatkit_domain_key = ENV["CHATKIT_DOMAIN_KEY"].presence
  # Popup framing. Defaults are http://localhost:3000 and http://127.0.0.1:3000.
  # Staging and production: CHATKIT_ALLOWED_ORIGINS is a comma-separated list of origins.
  # config.chatkit_allowed_origins = ENV["CHATKIT_ALLOWED_ORIGINS"] if ENV["CHATKIT_ALLOWED_ORIGINS"].present?
  # config.sign_in_path = "/users/sign_in"
  # Hash or lambda { |controller, purpose| }. Per-call chatkit_options override this.
  # Keys match ChatKit: startScreen, theme, header, composer, history, initialThread.
  # config.chatkit_options = {}
end
