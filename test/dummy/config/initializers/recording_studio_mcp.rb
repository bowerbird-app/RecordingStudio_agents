# frozen_string_literal: true

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
end

Rails.application.config.to_prepare do
  RecordingStudioMcp.register_type(
    type: "PressKit",
    description: "A press kit in a workspace. Use list to find one, show to read it, and update to change its name, description, or content."
  )
  RecordingStudioMcp.register_server(:public, api: :public) do
    include_tools(
      :list, :show, :create, :update, :delete,
      *RecordingStudioAgents::McpCopy.tool_names
    )
  end
end
