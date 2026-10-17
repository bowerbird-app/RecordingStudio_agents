# frozen_string_literal: true

RecordingStudioAgents.configure do |config|
  config.instructions = "Answer in one sentence."
  config.chatkit_domain_key = ENV["CHATKIT_DOMAIN_KEY"].presence
  config.request_actor = lambda do |controller|
    user = controller.request.env["warden"]&.user(:user)
    Current.actor = user if defined?(Current)
    user
  end
  config.request_root = lambda do |_controller|
    workspace = Workspace.order(:created_at).first
    workspace && RecordingStudio.root_recording_for(workspace)
  end
end
