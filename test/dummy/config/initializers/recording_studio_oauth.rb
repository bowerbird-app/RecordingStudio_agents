# frozen_string_literal: true

RecordingStudioOauth.configure do |config|
  config.authentication_method = :authenticate_user!
  config.current_actor_method = :current_user
  config.api_mount_path = "/recording_studio_api"
  config.engine_mount_path = "/recording_studio_oauth"
  config.mcp_mount_path = "/recording_studio_mcp"
  config.register_origin_as_protected_resource = false
  config.allow_self_registered_apps = false
end
