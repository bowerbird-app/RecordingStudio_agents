# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    module Queries
      module_function

      def agents
        RecordingStudioAgents.agents.all
      end

      def skills
        RecordingStudioAgents.skills.all
      end

      def tasks(context:)
        Task.where(root_recording_id: visible_root_ids(context)).order(created_at: :desc)
      end

      def runs(context:)
        AgentRun.where(root_recording_id: visible_root_ids(context)).order(created_at: :desc)
      end

      def evaluations(context:)
        Evaluation.joins(:agent_run).where(
          recording_studio_agents_agent_runs: { root_recording_id: visible_root_ids(context) }
        ).order(created_at: :desc)
      end

      def recent_failed_runs(context:)
        runs(context: context).where(status: "failed").limit(5)
      end

      def run_count(context:)
        runs(context: context).count
      end

      def visible_root_ids(context)
        actor = context.current_actor
        return [] if actor.blank? || !defined?(::RecordingStudioAccessible)

        ::RecordingStudioAccessible.root_recording_ids_for(actor: actor, minimum_role: :view)
      end
    end
  end
end
