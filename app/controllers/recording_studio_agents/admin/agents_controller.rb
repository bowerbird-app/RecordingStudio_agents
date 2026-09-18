# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class AgentsController < RecordingStudioAdmin::ApplicationController
      def turn_on
        change_enabled!(:turn_on, true)
      end

      def turn_off
        change_enabled!(:turn_off, false)
      end

      private

      def change_enabled!(action_key, enabled)
        agent = load_agent!
        perform_recording_studio_admin_action!("registered_agents", action_key, agent) do
          Enablement.set!(agent: agent, enabled: enabled)
        end

        redirect_to recording_studio_admin_context.admin_screen_path("registered_agents"),
                    notice: enabled ? "#{agent.name} is on." : "#{agent.name} is off."
      rescue ConfigurationError
        head :not_found
      end

      def load_agent!
        RecordingStudioAgents.agents.fetch(params[:agent_key], version: params[:version])
      rescue ConfigurationError
        raise ActiveRecord::RecordNotFound
      end

      def recording_studio_admin_context
        @recording_studio_admin_context ||= RecordingStudioAdmin::Context.new(
          params: params.to_unsafe_h,
          current_actor: current_actor,
          controller: self,
          routes: self,
          view_context: view_context,
          surface: RecordingStudioAdmin.configuration.surface_for("admin")
        )
      end

      def current_root_recording
        nil
      end
    end
  end
end
