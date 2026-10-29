# frozen_string_literal: true

require "test_helper"

class SignedInAuthorizationTest < Minitest::Test
  def test_a_signed_in_actor_may_execute
    attribution = Struct.new(:initiator).new(Object.new)

    allowed = RecordingStudioAgents::SignedInAuthorization.call(
      action: "recording_studio_ai.execute",
      attribution: attribution,
      context: {}
    )

    assert_equal true, allowed
  end

  def test_a_missing_actor_may_not_execute
    attribution = Struct.new(:initiator).new(nil)

    allowed = RecordingStudioAgents::SignedInAuthorization.call(
      action: "recording_studio_ai.execute",
      attribution: attribution
    )

    assert_equal false, allowed
  end

  def test_popup_policy_names_chatkit_hosts_and_frame_ancestors
    configuration = RecordingStudioAgents.configuration
    previous = configuration.chatkit_allowed_origins.dup
    configuration.chatkit_allowed_origins = ["https://staging.example"]
    policy = ActionDispatch::ContentSecurityPolicy.new

    RecordingStudioAgents::ChatKit::ContentSecurityPolicy.apply(policy)
    header = policy.build

    assert_includes header, "script-src 'self' 'unsafe-inline' https://cdn.platform.openai.com"
    assert_includes header, "connect-src 'self' https://cdn.platform.openai.com https://api.openai.com"
    assert_includes header, "frame-src 'self' https://cdn.platform.openai.com"
    assert_includes header, "frame-ancestors 'self' https://staging.example"
  ensure
    configuration.chatkit_allowed_origins = previous if configuration && previous
  end

  def test_other_actions_stay_denied
    attribution = Struct.new(:initiator).new(Object.new)

    allowed = RecordingStudioAgents::SignedInAuthorization.call(
      action: "recording_studio_ai.view_execution",
      attribution: attribution
    )

    assert_equal false, allowed
  end
end
