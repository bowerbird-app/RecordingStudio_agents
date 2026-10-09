# frozen_string_literal: true

RecordingStudio.configure do |config|
  config.recordable_types = ["Workspace", "Folder", "Page", "AdminRoot"]
  config.require_recordable_declarations = true
  config.app_name = "Agents" if config.respond_to?(:app_name=)
  config.actor = -> { Current.actor }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.recordable_dup_strategy = :dup
end
