# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  config.access_actor_types = [ "User", "RecordingStudioOauth::OauthAuthorization" ]
  config.admin_root_resolver = -> { RecordingStudio.root_recording_for(Workspace.find_by!(name: "Studio Workspace")) }
end
