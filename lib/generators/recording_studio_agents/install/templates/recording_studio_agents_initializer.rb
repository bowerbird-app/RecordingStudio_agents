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
  # Write-tool calls allowed in one provider turn, including a resumed stream.
  # The default is 3. Earlier writes for that turn count. The count and the pending
  # audit row share a PostgreSQL advisory lock for that turn. A later write comes back as
  # "write limit reached" and the turn continues. Reads are still answered.
  # config.mcp_max_writes_per_turn = 3
  # Tool names. Nil allows every tool the mode permits. An empty allow list blocks
  # every tool. Deny wins when a name is on both lists. Applied when tools are
  # listed and when a call runs.
  # config.mcp_tool_allow = nil
  # config.mcp_tool_deny = []
  # Popup utility stylesheet. Nil skips the tag. The default is "tailwind".
  # config.popup_stylesheet = "tailwind"
  # Set false and recording_studio_agents_launcher renders nothing. The default is on.
  # config.launcher = false

  # Signed-in person for ChatKit and the popup. current_user when the controller
  # has it. A mounted engine controller usually does not, so the host session
  # (Warden) is the fallback. Sets Current.actor only when that writer exists.
  config.request_actor = lambda do |controller|
    user = controller.send(:current_user) if controller.respond_to?(:current_user, true)
    user ||= controller.request.env["warden"]&.user(:user) if controller.respond_to?(:request)
    Current.actor = user if defined?(Current) && Current.respond_to?(:actor=)
    user
  end

  # Workspace for that person. Root Switchable's current root, not the oldest one.
  config.request_root = lambda do |controller|
    actor = defined?(Current) ? Current.actor : nil
    actor = controller.send(:current_user) if actor.blank? && controller.respond_to?(:current_user, true)
    actor ||= controller.request.env["warden"]&.user(:user) if controller.respond_to?(:request)
    next if actor.blank?
    next unless defined?(RecordingStudio::RootSwitchable)

    device_key = RecordingStudio::RootSwitchable::DeviceKey.fetch(controller: controller)
    RecordingStudio::RootSwitchable.resolve_current_root(
      controller: controller,
      actor: actor,
      device_key: device_key
    ).root_recording
  rescue RecordingStudio::RootSwitchable::DeviceKey::Unavailable
    nil
  end
end
