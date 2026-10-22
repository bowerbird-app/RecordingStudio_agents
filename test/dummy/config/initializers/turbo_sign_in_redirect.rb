# frozen_string_literal: true

# Users signs in with redirect_to, which is 302. Turbo Drive does not treat a
# 302 after a POST as a finished form, so the sign-in form looks stuck.
# 303 tells Turbo the POST is done and the next step is GET.
Rails.application.config.to_prepare do
  RecordingStudioUser::Auth::PendingEmail.module_eval do
    def finish_sign_in!(user)
      clear_pending_auth_email!
      sign_in_user!(user)
      redirect_to after_sign_in_path_for(user), status: :see_other
    end

    def finish_sign_up!(user)
      clear_pending_auth_email!
      sign_in_user!(user)
      redirect_to after_sign_up_path_for(user), status: :see_other
    end
  end
end
