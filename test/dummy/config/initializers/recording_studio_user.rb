# frozen_string_literal: true

RecordingStudioUser.configure do |config|
  config.user_class_name = "User"
  config.mount_path = "/account"

  # Auth screens stay on the host application layout. Other Users pages follow
  # Recording Studio's layout. Users 0.28 resolves this through Layout.accept.
  config.layout = lambda do |controller:|
    "application" if controller.is_a?(RecordingStudioUser::Auth::BaseController)
  end
end
