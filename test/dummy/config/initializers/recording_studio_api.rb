# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  config.admin_root_recordable_type_names = ["Workspace"]
  config.openapi_title = "Recording Studio API"
  config.openapi_description = "Resource server for Recording Studio. MCP calls the same actions."
  config.documentation_enabled = false
  config.rate_limit_oauth_enabled = false if config.respond_to?(:rate_limit_oauth_enabled=)
  config.rate_limit_api_pre_auth_enabled = false if config.respond_to?(:rate_limit_api_pre_auth_enabled=)
  config.rate_limit_api_enabled = false if config.respond_to?(:rate_limit_api_enabled=)
  config.api_request_logging_enabled = false if config.respond_to?(:api_request_logging_enabled=)
end

RecordingStudioApi.register_recordable_type_api(
  "PressKit",
  serializer: ->(press_kit, **) {
    { name: press_kit.name, description: press_kit.description, content: press_kit.content }
  },
  output_keys: %i[name description content],
  writable_attributes: %i[name description content],
  operations: %i[index show update]
)
