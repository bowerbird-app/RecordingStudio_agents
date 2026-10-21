# frozen_string_literal: true

RecordingStudioAgents.configure do |config|
  # config.instructions = "Answer in plain language."
  # Nobody may pass a per-chat override until this is :admin or :edit. There is no replace mode.
  # config.instructions_override = :none
  # config.max_instructions_length = 4000
  # config.default_profile = :medium
  # config.purpose = "agent_chat"
  # config.provider = "openai"
  # config.retention_period = 30.days
  # config.chatkit_domain_key = ENV.fetch("CHATKIT_DOMAIN_KEY", nil)
  # Hash or lambda { |controller, purpose| }. Per-call chatkit_options override this.
  # Keys match ChatKit: startScreen, theme, header, composer, history, initialThread.
  # config.chatkit_options = {}
end
