# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class AgentsController < ::ApplicationController
      include RecordingStudioAdmin::AdminActionAuditing

      def turn_on
        toggle!(:turn_on, true)
      end

      def turn_off
        toggle!(:turn_off, false)
      end

      private

      def toggle!(action_key, enabled)
        agent = load_agent!
        perform_recording_studio_admin_action!("registered_agents", action_key, agent) do
          Enablement.set!(agent: agent, enabled: enabled)
        end

        redirect_to recording_studio_admin_context.admin_screen_path("registered_agents"),
                    notice: enabled ? "#{agent.name} is on." : "#{agent.name} is off."
      rescue RecordingStudioAdmin::AuthorizationFailed, RecordingStudioAdmin::DefinitionNotFound
        head :forbidden
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
          current_actor: current_admin_actor,
          controller: self,
          routes: self,
          view_context: view_context,
          surface: RecordingStudioAdmin.configuration.surface_for("admin")
        )
      end

      def current_admin_actor
        return Current.actor if defined?(Current) && Current.respond_to?(:actor) && !Current.actor.nil?

        method_name = RecordingStudioAdmin.configuration.current_actor_method
        send(method_name) if method_name && respond_to?(method_name, true)
      end
    end
  end
end
