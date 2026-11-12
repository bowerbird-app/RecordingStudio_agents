# frozen_string_literal: true

require "test_helper"

class ApiActorTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAgents.configuration
    @previous_tools = @configuration.mcp_tools
    @previous_logger = Rails.logger
    @messages = []
    @logger = Object.new
    messages = @messages
    @logger.define_singleton_method(:warn) { |message| messages << message }
    Rails.logger = @logger
  end

  def teardown
    @configuration.mcp_tools = @previous_tools
    Rails.logger = @previous_logger
  end

  def test_boot_wires_the_warning_after_host_initializers
    initializer = RecordingStudioAgents::Engine.initializers.find do |entry|
      entry.name == "recording_studio_agents.api_actor_warning"
    end

    assert initializer
    assert_equal :load_config_initializers, initializer.after
  end

  def test_warns_when_writes_are_on_and_api_is_older_than_0_20
    @configuration.mcp_tools = :write

    with_api_version("0.16.0") { RecordingStudioAgents::Mcp::ApiActor.warn_if_needed }

    message = @messages.join
    assert_includes message, "event.actor will be empty for agent writes"
    assert_includes message, "Upgrade recording_studio_api to 0.20 or later"
    assert_includes message, "0.16.0"
  end

  def test_does_not_warn_for_a_current_api_read_only_tools_or_a_missing_gem
    @configuration.mcp_tools = :write
    with_api_version("0.20.0") { RecordingStudioAgents::Mcp::ApiActor.warn_if_needed }
    with_api_version("0.21.0") { RecordingStudioAgents::Mcp::ApiActor.warn_if_needed }

    @configuration.mcp_tools = :read
    with_api_version("0.16.0") { RecordingStudioAgents::Mcp::ApiActor.warn_if_needed }

    @configuration.mcp_tools = :off
    with_api_version("0.19.9") { RecordingStudioAgents::Mcp::ApiActor.warn_if_needed }

    @configuration.mcp_tools = :write
    without_api { RecordingStudioAgents::Mcp::ApiActor.warn_if_needed }

    assert_empty @messages
  end

  private

  def with_api_version(version, &)
    spec = Gem::Specification.new("recording_studio_api", version)
    with_loaded_specs({ "recording_studio_api" => spec }, &)
  end

  def without_api(&)
    with_loaded_specs({}, &)
  end

  def with_loaded_specs(specs, &)
    Gem.stub(:loaded_specs, specs, &)
  end
end
