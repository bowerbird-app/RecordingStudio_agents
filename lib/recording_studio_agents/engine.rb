# frozen_string_literal: true

require "recording_studio_agents/filter_instructions"

module RecordingStudioAgents
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioAgents

    initializer "recording_studio_agents.filter_instructions", before: "active_record.set_filter_attributes" do |app|
      FilterInstructions.apply(app)
    end

    initializer "recording_studio_agents.filter_instructions_loaded", after: :load_config_initializers do |app|
      FilterInstructions.apply(app)
    end

    # Run before_initialize hooks
    initializer "recording_studio_agents.before_initialize", before: "recording_studio_agents.load_config" do |_app|
      RecordingStudioAgents.configuration.hooks.run(:before_initialize, self)
    end

    initializer "recording_studio_agents.load_config" do |app|
      # Load config/recording_studio_agents.yml via Rails config_for if present
      if app.respond_to?(:config_for)
        begin
          yaml = begin
            app.config_for(:recording_studio_agents)
          rescue StandardError
            nil
          end
          RecordingStudioAgents.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError => _e
          # ignore load errors; host app can provide initializer overrides
        end
      end

      # Merge Rails.application.config.x.recording_studio_agents if present
      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_agents)
        xcfg = app.config.x.recording_studio_agents
        if xcfg.respond_to?(:to_h)
          RecordingStudioAgents.configuration.merge!(xcfg.to_h)
        else
          begin
            # try converting OrderedOptions
            hash = {}
            xcfg.each_pair { |k, v| hash[k] = v } if xcfg.respond_to?(:each_pair)
            RecordingStudioAgents.configuration.merge!(hash) if hash&.any?
          rescue StandardError => _e
            # ignore
          end
        end
      end

      # Run on_configuration hooks after config is loaded
      RecordingStudioAgents.configuration.hooks.run(:on_configuration, RecordingStudioAgents.configuration)
    end

    # Run after_initialize hooks
    initializer "recording_studio_agents.after_initialize", after: "recording_studio_agents.load_config" do |_app|
      RecordingStudioAgents.configuration.hooks.run(:after_initialize, self)
    end

    initializer "recording_studio_agents.chatkit_helper" do
      ActiveSupport.on_load(:action_controller_base) do
        helper RecordingStudioAgents::ChatKitHelper
      end
    end

    initializer "recording_studio_agents.recordables" do
      config.to_prepare do
        RecordingStudio.register_recordable_type("RecordingStudioAgents::Session")
      end
    end

    initializer "recording_studio_agents.mcp" do
      config.to_prepare { RecordingStudioAgents::Mcp.register! }
    end
  end
end
