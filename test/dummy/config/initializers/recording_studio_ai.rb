# frozen_string_literal: true

RecordingStudioAI.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  config.authorization_handler = RecordingStudioAI::AccessibleAuthorization.method(:call)
  config.custom_tool_confirmation_handler = lambda do |definition:, **|
    definition.requires_confirmation ? :pending : :approved
  end
  config.admin_actor_resolver = ->(controller:) { Current.actor }
  config.admin_authenticate = ->(controller:) { controller.authenticate_user! }
  config.admin_visible_roots_resolver = lambda do |actor:, controller:|
    RecordingStudioAI::AccessibleAuthorization.accessible_root_ids(actor: actor, minimum_role: :view)
  end
  config.admin_layout = "recording_studio/default_layout"
end
