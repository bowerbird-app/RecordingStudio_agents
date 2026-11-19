# frozen_string_literal: true

require "test_helper"

class SessionsEnabledTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAgents.configuration
    @previous = @configuration.enabled
    @provider_calls = 0
  end

  def teardown
    @configuration.enabled = @previous
  end

  def test_create_and_append_raise_before_the_provider_when_agents_are_off
    assert_operator RecordingStudioAgents::DisabledError, :<, RecordingStudioAgents::Error

    RecordingStudioAI::Agents.stub(:create_session, ->(**) { @provider_calls += 1 }) do
      RecordingStudioAI::Agents.stub(:send_input, ->(**) { @provider_calls += 1 }) do
        [false, -> { false }, ->(*) { raise "token=secret-value" }].each do |flag|
          @configuration.enabled = flag
          assert_raises(RecordingStudioAgents::DisabledError) { create_chat }
          assert_raises(RecordingStudioAgents::DisabledError) { append_chat }
        end
      end
    end

    assert_equal 0, @provider_calls
  end

  private

  def create_chat
    RecordingStudioAgents::Sessions::Create.call(
      parent_recording: Object.new, root_recording: Object.new, actor: Object.new,
      input: "hello", idempotency_key: "create-off"
    )
  end

  def append_chat
    RecordingStudioAgents::Sessions::Append.call(
      root_recording: Object.new, actor: Object.new, input: "again", idempotency_key: "append-off"
    )
  end
end
