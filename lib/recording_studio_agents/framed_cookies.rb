# frozen_string_literal: true

module RecordingStudioAgents
  # Session and CSRF cookies for a popup framed by another site.
  #
  # Embeddable's widget does not use the host session. This popup does, so the
  # session cookie is marked the same way as the CSRF cookie when the request
  # is HTTPS. Browsers reject SameSite=None without Secure, and Rails will not
  # write a Secure session cookie on plain HTTP.
  module FramedCookies
    extend ActiveSupport::Concern

    included do
      prepend_before_action :prepare_framed_cookies
    end

    def verified_request?
      super || framed_csrf_cookie_matches?
    end

    private

    def prepare_framed_cookies
      mark_framed_session_cookie if request.ssl?
      form_authenticity_token
      raw = request.env[ActionController::RequestForgeryProtection::CSRF_TOKEN]
      ChatKit::CsrfCookieStore.new.store(request, raw) if raw.present?
    end

    def mark_framed_session_cookie
      request.session_options[:same_site] = :none
      request.session_options[:secure] = true
      request.session_options[:partitioned] = true
    end

    def framed_csrf_cookie_matches?
      presented = presented_csrf_token
      return false if presented.nil?

      ActiveSupport::SecurityUtils.fixed_length_secure_compare(presented, framed_csrf_cookie_token)
    rescue ArgumentError
      false
    end

    def presented_csrf_token
      encoded = request.headers["X-CSRF-Token"].presence || params[:authenticity_token].presence
      return if encoded.blank?

      unmasked_csrf_token(encoded.to_s)
    end

    def framed_csrf_cookie_token
      stored = ChatKit::CsrfCookieStore.new.fetch(request)
      return "".b if stored.blank?

      decode_csrf_token(stored)
    end

    def unmasked_csrf_token(encoded)
      masked = decode_csrf_token(encoded)
      length = ActionController::RequestForgeryProtection::AUTHENTICITY_TOKEN_LENGTH
      return masked if masked.bytesize == length
      return unmask_token(masked) if masked.bytesize == length * 2

      nil
    end
  end
end
