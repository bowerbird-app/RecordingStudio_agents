# frozen_string_literal: true

require "test_helper"

class TurboDriveTest < ActionDispatch::IntegrationTest
  test "sign in failure is 422 and sign in and sign out redirect with 303" do
    user = User.create!(email: "turbo-#{SecureRandom.hex(4)}@example.com", password: "Password")
    headers = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    post user_session_path, params: { user: { email: user.email, password: "nope" } }, headers: headers
    assert_response :unprocessable_content

    post user_session_path, params: { user: { email: user.email, password: "Password" } }, headers: headers
    assert_response :see_other

    delete destroy_user_session_path, headers: headers
    assert_response :see_other
  end
end
