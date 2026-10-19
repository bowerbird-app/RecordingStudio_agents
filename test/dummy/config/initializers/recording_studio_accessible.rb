# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  config.access_actor_types = [ "User", "RecordingStudioOauth::OauthAuthorization" ]
end
