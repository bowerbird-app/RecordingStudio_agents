# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # CSRF token for the cross-site popup iframe.
    #
    # Mirrors RecordingStudioEmbeddable::FloatingWidget::CsrfCookieStore.
    # This gem does not depend on Embeddable. Embeddable scopes the cookie to
    # the widget document because that document posts to itself. The popup
    # posts to /chatkit, so this cookie uses the engine mount path.
    class CsrfCookieStore
      COOKIE = "recording_studio_agents_popup_csrf"

      def fetch(request)
        request.cookie_jar.encrypted[COOKIE]
      end

      def store(request, csrf_token)
        request.cookie_jar.encrypted[COOKIE] = cookie_options(request).merge(value: csrf_token)
      end

      def reset(request)
        request.cookie_jar.delete(COOKIE, cookie_options(request))
      end

      private

      def cookie_options(request)
        {
          httponly: true,
          secure: true,
          same_site: :none,
          partitioned: true,
          path: mount_path(request)
        }
      end

      def mount_path(request)
        script_name = request.script_name.to_s
        return "/" if script_name.empty?

        script_name.delete_suffix("/")
      end
    end
  end
end
