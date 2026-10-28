# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioAgents.instance_variable_get(:@configuration)
    RecordingStudioAgents.instance_variable_set(:@configuration, RecordingStudioAgents::Configuration.new)
  end

  def teardown
    RecordingStudioAgents.configuration.hooks.clear!
    RecordingStudioAgents.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_before_and_after_initialize_initializers_run_hooks
    before_called = false
    after_called = false

    RecordingStudioAgents.configuration.hooks.before_initialize { |_engine| before_called = true }
    RecordingStudioAgents.configuration.hooks.after_initialize { |_engine| after_called = true }

    find_initializer("recording_studio_agents.before_initialize").block.call(Object.new)
    find_initializer("recording_studio_agents.after_initialize").block.call(Object.new)

    assert before_called
    assert after_called
  end

  def test_load_config_merges_config_sources_and_runs_on_configuration_hook
    hook_called = false
    hook_payload = nil
    RecordingStudioAgents.configuration.hooks.on_configuration do |cfg|
      hook_called = true
      hook_payload = cfg
    end

    xcfg = Struct.new(:recording_studio_agents).new({ purpose: "support_chat" })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { instructions: "from_yaml", retention_period: 12 }
      end
    end.new(app_config)

    find_initializer("recording_studio_agents.load_config").block.call(app)

    assert hook_called
    assert_equal RecordingStudioAgents.configuration, hook_payload
    assert_equal "from_yaml", RecordingStudioAgents.configuration.instructions
    assert_equal 12.seconds, RecordingStudioAgents.configuration.retention_period
    assert_equal "support_chat", RecordingStudioAgents.configuration.purpose
  end

  def test_load_config_handles_errors_and_each_pair_fallback
    pair_config = Class.new do
      def each_pair
        yield(:retention_period, 15)
      end
    end.new

    xcfg = Struct.new(:recording_studio_agents).new(pair_config)
    app_config = Struct.new(:x).new(xcfg)

    app = Struct.new(:config) do
      def config_for(_name)
        raise "missing file"
      end
    end.new(app_config)

    find_initializer("recording_studio_agents.load_config").block.call(app)

    assert_equal 15.seconds, RecordingStudioAgents.configuration.retention_period
  end

  def test_load_config_swallow_each_pair_errors
    bad_pair_config = Class.new do
      def each_pair
        raise "bad pair"
      end
    end.new

    xcfg = Struct.new(:recording_studio_agents).new(bad_pair_config)
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { instructions: "ok" }
      end
    end.new(app_config)

    # Should not raise even if xcfg.each_pair fails.
    find_initializer("recording_studio_agents.load_config").block.call(app)

    assert_equal "ok", RecordingStudioAgents.configuration.instructions
  end

  def test_load_config_is_noop_without_config_sources
    app = Struct.new(:config).new(Object.new)

    find_initializer("recording_studio_agents.load_config").block.call(app)

    assert_equal "Answer in plain language.", RecordingStudioAgents.configuration.instructions
    assert_equal 30.days, RecordingStudioAgents.configuration.retention_period
    assert_equal :medium, RecordingStudioAgents.configuration.default_profile
  end

  def test_load_config_ignores_non_enumerable_yaml_and_merge_errors
    yaml = Class.new do
      def each
        raise "bad yaml"
      end
    end.new

    xcfg = Struct.new(:recording_studio_agents).new({ retention_period: 22 })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      attr_accessor :yaml

      def config_for(_name)
        @yaml
      end
    end.new(app_config)
    app.yaml = yaml

    find_initializer("recording_studio_agents.load_config").block.call(app)

    assert_equal 22.seconds, RecordingStudioAgents.configuration.retention_period
  end

  def test_template_extension_installer_and_engine_root_are_gone
    refute File.exist?(File.expand_path("../lib/recording_studio_agents/extension_installer.rb", __dir__))
    refute File.exist?(File.expand_path("../app/controllers/recording_studio_agents/home_controller.rb", __dir__))
    assert_nil find_initializer("recording_studio_agents.apply_model_extensions")
    assert_nil find_initializer("recording_studio_agents.apply_controller_extensions")
    refute(RecordingStudioAgents::Engine.routes.routes.any? { |route| route.name == "root" })
  end

  private

  def find_initializer(name)
    RecordingStudioAgents::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
