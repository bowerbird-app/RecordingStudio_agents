# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class Section < RecordingStudioAdmin::Section
      key "agents"
      icon :sparkles
      title "Agents admin"
      subtitle "Who ran, what they tried, and how heavy the model calls were."

      link :agents,
           text: "Agents",
           url: ->(context) { context.admin_screen_path("registered_agents") }
      link :runs,
           text: "Runs",
           url: ->(context) { context.admin_screen_path("agent_runs") }
      link :tasks,
           text: "Tasks",
           url: ->(context) { context.admin_screen_path("agent_tasks") }
      link :usage,
           text: "Usage by agent",
           url: ->(context) { context.admin_screen_path("agent_usage") }
      link :evaluations,
           text: "Evaluations",
           url: ->(context) { context.admin_screen_path("agent_evaluations") }
      # Admin only enables screens linked from a section. Keep this off the
      # hub unless an agent is selected, so a name can open the details page.
      link :agent,
           text: "Agent",
           url: ->(context) { context.admin_screen_path("registered_agent") },
           visible_if: ->(context) { Queries.selected_agent_key(context).present? }

      widget "widgets.agents.failed_runs"
      widget "widgets.agents.attempts_this_period"
      widget "widgets.agents.tokens_this_period"
      widget "widgets.agents.hungry_agents"
    end
  end
end
