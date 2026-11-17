# frozen_string_literal: true

# recording_studio_ai.execute maps to :edit on the workspace through Accessible.
# Do not allow every signed-in person.
RecordingStudioAI.configure do |config|
  config.authorization_handler = RecordingStudioAI::AccessibleAuthorization.method(:call)
  # Off unless RECORDING_STUDIO_AGENTS_DECLINE_CREDITS=1. Not the default.
  if ENV["RECORDING_STUDIO_AGENTS_DECLINE_CREDITS"] == "1"
    config.usage_handler = ->(**) { nil }
    config.usage_precheck = ->(**) { false }
    config.credit_prices = { "*" => { input: 0 } }
  end
end
