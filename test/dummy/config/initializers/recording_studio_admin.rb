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

# Admin opens on the staff root, while playground and demo calls are stored on a
# workspace. Model call screens need both, or a workspace call looks missing.
module RecordingStudioAdminWorkspaceRuns
  def runs_scope(context = admin_context)
    bind_admin_context!(context) if context
    root_ids = []
    root_ids << context.root_recording.id if context&.root_recording
    root_ids.concat(
      RecordingStudio::Recording.where(recordable_type: "Workspace", trashed_at: nil).pluck(:id)
    )
    root_ids.uniq!
    return RecordingStudioAI::Run.none if root_ids.empty?

    RecordingStudioAI::Run.where(root_recording_id: root_ids)
  end
end

module RecordingStudioAdminIgnoreProductRoot
  def current_root_recording
    nil
  end
end

Rails.application.config.to_prepare do
  gem_controllers = []
  if defined?(RecordingStudioAdmin::ApplicationController)
    gem_controllers << RecordingStudioAdmin::ApplicationController
  end
  if defined?(RecordingStudioAccessible::ApplicationController)
    gem_controllers << RecordingStudioAccessible::ApplicationController
  end

  gem_controllers.each do |controller|
    next if controller.ancestors.include?(RecordingStudio::UsesDefaultLayout)

    controller.include(RecordingStudio::UsesDefaultLayout)
  end

  if defined?(RecordingStudioAdmin::ApplicationController) &&
     !RecordingStudioAdmin::ApplicationController.ancestors.include?(RecordingStudioAdminIgnoreProductRoot)
    RecordingStudioAdmin::ApplicationController.prepend(RecordingStudioAdminIgnoreProductRoot)
  end

  if defined?(AdminScreens::RecordingStudioAIWidgets) &&
     !AdminScreens::RecordingStudioAIWidgets.singleton_class.ancestors.include?(RecordingStudioAdminWorkspaceRuns)
    AdminScreens::RecordingStudioAIWidgets.singleton_class.prepend(RecordingStudioAdminWorkspaceRuns)
  end

  if defined?(AdminScreens::RootSection)
    AdminScreens.send(:remove_const, :RootSection)
  end
  load Rails.root.join("app/admin/root/section.rb")
  RecordingStudioAdmin.register_section(AdminScreens::RootSection)
end
