# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    module Widgets
      FAILED_RUNS = RecordingStudioAdmin::Widget.new("widgets.agents.failed_runs") do
        type :list
        title "Failed runs"
        info "The last attempts that did not finish. Open Runs to retry from the host."
        hide_change
        hide_period
        items do |context|
          Queries.recent_failed_runs(context: context).map do |run|
            {
              text: "#{run.agent_key} · #{run.failure_code || 'failed'}",
              href: context.admin_screen_path("agent_runs")
            }
          end
        end
      end

      RUN_COUNT = RecordingStudioAdmin::Widget.new("widgets.agents.run_count") do
        type :number
        title "Runs"
        info "How many attempts are on record for workspaces you can see."
        value { |context| Queries.run_count(context: context) }
        hide_change
        hide_period
      end
    end
  end
end
