# frozen_string_literal: true

require "test_helper"

class AIProvidersTest < ActiveSupport::TestCase
  test "host provider keys stay unread while the suite is offline" do
    with_env(
      "GEMINI_API_KEY" => "gemini-secret",
      "google_ai_studio" => "studio-secret",
      "TYPESAFE_API_KEY" => "typesafe-secret",
      "typesafe" => "jev-secret"
    ) do
      assert_nil DummyAIProviderKeys.read("GEMINI_API_KEY", "google_ai_studio", offline: true)
      assert_nil DummyAIProviderKeys.read("TYPESAFE_API_KEY", "typesafe", offline: true)
      assert_equal "gemini-secret", DummyAIProviderKeys.read("GEMINI_API_KEY", "google_ai_studio", offline: false)
      assert_equal "studio-secret", DummyAIProviderKeys.read("google_ai_studio", offline: false)
      assert_equal "jev-secret", DummyAIProviderKeys.read("typesafe", offline: false)
    end

    configuration = RecordingStudioAI.configuration
    assert_nil configuration.gemini_api_key
    assert_nil configuration.typesafe_api_key
    assert_nil configuration.openai_api_key
  end

  test "profiles send generation to Gemini and decisions to Jev" do
    configuration = RecordingStudioAI.configuration

    %i[low medium high].each do |profile|
      providers = configuration.profiles.fetch(profile).map { |entry| entry.fetch(:provider) }

      assert_equal %i[gemini typesafe], providers
      assert_equal "jev-latest", configuration.profiles.fetch(profile).last.fetch(:model)
    end
    assert_equal %i[gemini typesafe], configuration.allowed_provider_overrides.map(&:to_sym)

    with_provider_keys(gemini_api_key: "gemini-test", typesafe_api_key: "typesafe-test") do
      resolver = RecordingStudioAI::Resolver.new(configuration: configuration)
      generation = resolver.resolve(profile: :medium, required_capabilities: %i[generation custom_tools])
      decision = resolver.resolve(profile: :medium, required_capabilities: %i[decision decision_noul])

      assert_equal :gemini, generation.provider
      assert_equal "gemini-2.5-pro", generation.model
      assert_equal :typesafe, decision.provider
      assert_equal "jev-latest", decision.model
    end
  end

  test "the librarian demo calls the live generator only when Gemini or OpenAI is configured" do
    controller = AgentsController.new

    with_provider_keys(gemini_api_key: nil, openai_api_key: nil) do
      seen_hook = nil
      controller.send(:with_generate_stub) { seen_hook = Thread.current[DummyGenerateStub::THREAD_KEY] }
      assert_respond_to seen_hook, :call
    end

    with_provider_keys(gemini_api_key: "gemini-test", openai_api_key: nil) do
      seen_hook = :unset
      controller.send(:with_generate_stub) { seen_hook = Thread.current[DummyGenerateStub::THREAD_KEY] }
      assert_nil seen_hook
    end
  ensure
    Thread.current[DummyGenerateStub::THREAD_KEY] = nil
  end

  test "decision runs are allowed by the history constraints" do
    connection = RecordingStudioAI::Run.connection
    runs = constraint_expression(connection, :recording_studio_ai_runs, "chk_rsai_runs_operation")
    responses = constraint_expression(connection, :recording_studio_ai_responses, "chk_rsai_responses_type")

    assert_includes runs, "decision"
    assert_includes responses, "decision"
  end

  private

  def with_env(updates)
    previous = updates.keys.to_h { |name| [name, ENV[name]] }
    updates.each { |name, value| ENV[name] = value }
    yield
  ensure
    previous.each do |name, value|
      value.nil? ? ENV.delete(name) : ENV[name] = value
    end
  end

  def with_provider_keys(gemini_api_key:, typesafe_api_key: nil, openai_api_key: nil)
    configuration = RecordingStudioAI.configuration
    previous = {
      gemini_api_key: configuration.gemini_api_key,
      typesafe_api_key: configuration.typesafe_api_key,
      openai_api_key: configuration.openai_api_key
    }
    configuration.gemini_api_key = gemini_api_key
    configuration.typesafe_api_key = typesafe_api_key
    configuration.openai_api_key = openai_api_key
    yield
  ensure
    previous.each { |name, value| configuration.public_send(:"#{name}=", value) }
  end

  def constraint_expression(connection, table, name)
    constraint = connection.check_constraints(table).find { |entry| entry.name == name }
    constraint.expression
  end
end
