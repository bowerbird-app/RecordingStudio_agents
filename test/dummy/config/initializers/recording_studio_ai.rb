# frozen_string_literal: true

# Any signed-in actor may run an agent chat. Other Recording Studio AI actions stay denied.
RecordingStudioAI.configure do |config|
  config.authorization_handler = RecordingStudioAgents::SignedInAuthorization.method(:call)
end
