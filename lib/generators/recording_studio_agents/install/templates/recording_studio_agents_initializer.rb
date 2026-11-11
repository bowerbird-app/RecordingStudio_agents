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
  # Popup framing. Development and test default to localhost:3000 and 127.0.0.1:3000.
  # Anywhere else the list is empty until you set it, so frame-ancestors stays 'self'.
  # config.chatkit_allowed_origins = ENV["CHATKIT_ALLOWED_ORIGINS"] if ENV["CHATKIT_ALLOWED_ORIGINS"].present?
  # Sign-in defaults to main_app.new_user_session_path when that route exists.
  # config.sign_in_path = "/login"
  # Hash or lambda { |controller, purpose| }. Per-call chatkit_options override this.
  # Keys match ChatKit: startScreen, theme, header, composer, history, initialThread.
  # config.chatkit_options = {}
  # Workspace tools the chat may call. :write is the default (reads and writes).
  # :read keeps read-only tools. :off sends none. Chat and item tools are never sent.
  # config.mcp_tools = :write
end
