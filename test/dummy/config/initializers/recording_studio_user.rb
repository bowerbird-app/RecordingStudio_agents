# frozen_string_literal: true

RecordingStudioUser.configure do |config|
  config.user_class_name = "User"
  config.mount_path = "/account"
  # Users 0.30 defaults this to 12. The dummy seeds and tests use "Password".
  config.minimum_password_length = 6

  # Auth screens stay on the host application layout. Other Users pages follow
  # Recording Studio's layout. Users resolves this through Layout.accept.
  config.layout = lambda do |controller:|
    "application" if controller.is_a?(RecordingStudioUser::Auth::BaseController)
  end
end
