# frozen_string_literal: true

require "test_helper"

class ChatkitContentSecurityPolicyTest < Minitest::Test
  def test_popup_policy_names_chatkit_hosts_and_frame_ancestors
    configuration = RecordingStudioAgents.configuration
    previous = configuration.chatkit_allowed_origins.dup
    configuration.chatkit_allowed_origins = ["https://staging.example"]
    policy = ActionDispatch::ContentSecurityPolicy.new

    RecordingStudioAgents::ChatKit::ContentSecurityPolicy.apply(policy)
    header = policy.build

    assert_includes header, "script-src 'self' https://cdn.platform.openai.com"
    refute_includes header, "unsafe-inline"
    assert_includes header, "connect-src 'self' https://cdn.platform.openai.com https://api.openai.com"
    assert_includes header, "frame-src 'self' https://cdn.platform.openai.com"
    assert_includes header, "frame-ancestors 'self' https://staging.example"
  ensure
    configuration.chatkit_allowed_origins = previous if configuration && previous
  end

  def test_an_empty_origin_list_allows_only_self
    configuration = RecordingStudioAgents.configuration
    previous = configuration.chatkit_allowed_origins.dup
    configuration.chatkit_allowed_origins = []
    policy = ActionDispatch::ContentSecurityPolicy.new

    RecordingStudioAgents::ChatKit::ContentSecurityPolicy.apply(policy)
    header = policy.build

    assert_includes header, "frame-ancestors 'self'"
    refute_includes header, "localhost"
    refute_includes header, "127.0.0.1"
  ensure
    configuration.chatkit_allowed_origins = previous if configuration && previous
  end
end
