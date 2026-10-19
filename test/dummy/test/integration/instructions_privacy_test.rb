# frozen_string_literal: true

require "test_helper"

class InstructionsPrivacyTest < ActiveSupport::TestCase
  test "stored instructions stay out of logs and inspect" do
    secret = "keep-this-private-#{SecureRandom.hex(4)}"
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    session = RecordingStudioAgents::Session.new(instructions: secret)

    assert_equal "[FILTERED]", filtered.filter(instructions: secret)[:instructions]
    assert_includes session.inspect, "[FILTERED]"
    refute_includes session.inspect, secret
  end
end
