# frozen_string_literal: true

RecordingStudioAdmin.configure do |config|
  config.default_mount_path = "/admin"
  config.authentication_method = :authenticate_user!
  config.current_actor_method = :current_user
  config.async_widgets.enabled = false

  config.access_recording_resolver = lambda do |_context|
    admin_root = AdminRoot.find_by(name: "Admin")
    next unless admin_root

    RecordingStudio::Recording.find_by(recordable: admin_root, trashed_at: nil)
  end
  config.site_admin_recording_resolver = config.access_recording_resolver
end

module RecordingStudioAdminIgnoreProductRoot
  def current_root_recording
    nil
  end
end

Rails.application.config.to_prepare do
  next unless defined?(RecordingStudioAdmin::ApplicationController)

  unless RecordingStudioAdmin::ApplicationController.ancestors.include?(RecordingStudio::UsesDefaultLayout)
    RecordingStudioAdmin::ApplicationController.include(RecordingStudio::UsesDefaultLayout)
  end

  unless RecordingStudioAdmin::ApplicationController.ancestors.include?(RecordingStudioAdminIgnoreProductRoot)
    RecordingStudioAdmin::ApplicationController.prepend(RecordingStudioAdminIgnoreProductRoot)
  end
end
