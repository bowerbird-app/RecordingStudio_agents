# frozen_string_literal: true

RecordingStudioAgents.configure do |config|
  config.instructions = "Answer in one sentence."
  config.chatkit_domain_key = ENV["CHATKIT_DOMAIN_KEY"].presence
  config.sign_in_path = "/users/sign_in"
  if ENV["CHATKIT_ALLOWED_ORIGINS"].present?
    config.chatkit_allowed_origins = ENV["CHATKIT_ALLOWED_ORIGINS"]
  end
  config.request_actor = lambda do |controller|
    user = controller.request.env["warden"]&.user(:user)
    Current.actor = user if defined?(Current)
    user
  end
  config.request_root = lambda do |controller|
    actor = Current.actor
    actor ||= controller.request.env["warden"]&.user(:user) if controller.respond_to?(:request)
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
