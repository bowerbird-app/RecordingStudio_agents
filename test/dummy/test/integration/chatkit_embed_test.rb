# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class ChatkitEmbedTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "embed-#{SecureRandom.hex(4)}@example.com", password: "Password")
    sign_in @user
    @configuration = RecordingStudioAgents.configuration
    @previous_domain_key = @configuration.chatkit_domain_key
    @previous_provider = @configuration.provider
    @ai = RecordingStudioAI.configuration
    @previous_api_key = @ai.openai_api_key
    @previous_client = @ai.openai_client
    @previous_gemini_key = @ai.gemini_api_key
    @previous_gemini_client = @ai.gemini_client
    @configuration.chatkit_domain_key = nil
    @configuration.provider = "openai"
    @ai.openai_api_key = nil
    @ai.openai_client = nil
  end

  teardown do
    @configuration.chatkit_domain_key = @previous_domain_key
    @configuration.provider = @previous_provider
    @ai.openai_api_key = @previous_api_key
    @ai.openai_client = @previous_client
    @ai.gemini_api_key = @previous_gemini_key
    @ai.gemini_client = @previous_gemini_client
  end

  test "an unconfigured page explains both keys and does not mount a chat" do
    get agent_chat_path

    assert_response :success
    assert_includes response.body, "ChatKit setup"
    assert_includes response.body, "OpenAI API key — not set"
    assert_includes response.body, "OPENAI_API_KEY"
    assert_includes response.body, "config/initializers/recording_studio_ai.rb"
    assert_includes response.body, "ChatKit domain key — not set"
    assert_includes response.body, "CHATKIT_DOMAIN_KEY"
    assert_includes response.body, "https://platform.openai.com/settings/organization/security/domain-allowlist"
    assert_select "openai-chatkit", count: 0
    refute_includes response.body, "cdn.platform.openai.com/deployments/chatkit/chatkit.js"
    refute_includes response.body, "data-composer"
  end

  test "a domain key alone still shows the setup notice" do
    @configuration.chatkit_domain_key = "domain_pk_test"

    get agent_chat_path

    assert_includes response.body, "OpenAI API key — not set"
    assert_includes response.body, "ChatKit domain key — set"
    assert_select "openai-chatkit", count: 0
  end

  test "a gemini provider reports that a hosted agent is unsupported" do
    @configuration.provider = "gemini"
    @ai.gemini_api_key = "gem-test"
    @configuration.chatkit_domain_key = "domain_pk_test"

    get agent_chat_path

    assert_response :success
    assert_includes response.body, "Hosted agent — not available"
    assert_includes response.body, "no hosted-agent model"
    assert_includes response.body, "ChatKit domain key — set"
    refute_includes response.body, "OpenAI API key"
    refute_includes response.body, "Gemini API key"
    refute_includes response.body, "config.gemini_api_key"
    assert_select "openai-chatkit", count: 0
  end

  test "an unknown provider uses a generic setup message" do
    @configuration.provider = " made-up "
    @configuration.chatkit_domain_key = "domain_pk_test"

    get agent_chat_path

    assert_response :success
    assert_includes response.body, "Hosted agent — not available"
    refute_includes response.body, "Made Up API key"
    refute_includes response.body, "config.made_up_api_key"
    refute_includes response.body, "config.made-up_api_key"
    assert_select "openai-chatkit", count: 0
  end

  test "a configured page mounts the official component against this endpoint" do
    @configuration.chatkit_domain_key = "domain_pk_test"
    @ai.openai_api_key = "sk-test"

    get agent_chat_path

    assert_response :success
    assert_select "openai-chatkit", count: 1
    assert_includes response.body, "https://cdn.platform.openai.com/deployments/chatkit/chatkit.js"
    assert_includes response.body, "/recording_studio_agents/chatkit"
    assert_includes response.body, "domain_pk_test"
    assert_includes response.body, "X-CSRF-Token"
    assert_includes response.body, 'credentials: "same-origin"'
    refute_includes response.body, "ChatKit setup"
    refute_includes response.body, "sk-test"
    refute_includes response.body, "data-composer"
  end
end
