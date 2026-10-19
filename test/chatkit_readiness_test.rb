# frozen_string_literal: true

require "test_helper"

class ChatkitReadinessTest < Minitest::Test
  def setup
    @agents = RecordingStudioAgents.configuration
    @ai = RecordingStudioAI.configuration
    @provider = @agents.provider
    @domain_key = @agents.chatkit_domain_key
    @openai_api_key = @ai.openai_api_key
    @openai_client = @ai.openai_client
    @gemini_api_key = @ai.gemini_api_key
    @gemini_client = @ai.gemini_client
    @agents.chatkit_domain_key = "domain_pk_test"
  end

  def teardown
    @agents.provider = @provider
    @agents.chatkit_domain_key = @domain_key
    @ai.openai_api_key = @openai_api_key
    @ai.openai_client = @openai_client
    @ai.gemini_api_key = @gemini_api_key
    @ai.gemini_client = @gemini_client
  end

  def test_openai_provider_reports_a_missing_api_key
    @agents.provider = "openai"
    @ai.openai_api_key = nil
    @ai.openai_client = nil

    assert_equal [:openai_api_key], readiness.missing
    assert_equal "OpenAI API key", readiness.credential_label
  end

  def test_openai_client_satisfies_the_provider_without_an_api_key
    @agents.provider = "openai"
    @ai.openai_api_key = nil
    @ai.openai_client = Object.new

    assert_empty readiness.missing
  end

  def test_another_provider_reports_its_own_missing_key
    @agents.provider = "gemini"
    @ai.openai_api_key = nil
    @ai.gemini_api_key = nil
    @ai.gemini_client = nil

    assert_equal [:gemini_api_key], readiness.missing
    assert_equal "Gemini API key", readiness.credential_label
    refute_includes readiness.missing, :openai_api_key
  end

  def test_another_provider_is_ready_with_its_own_key
    @agents.provider = "gemini"
    @ai.openai_api_key = nil
    @ai.gemini_api_key = "gem-test"

    assert_empty readiness.missing
    assert readiness.configured?
  end

  def test_a_blank_provider_follows_the_profile_hosted_model
    @agents.provider = nil
    @ai.openai_api_key = nil
    @ai.openai_client = nil

    assert_equal :openai, readiness.hosted_provider
    assert_includes readiness.missing, :openai_api_key
  end

  private

  def readiness
    RecordingStudioAgents::ChatKit::Readiness
  end
end
