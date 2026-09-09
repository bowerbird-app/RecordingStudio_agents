# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class Section < RecordingStudioAdmin::Section
      key "agents"
      icon :sparkles
      title "Agents"
      subtitle "Who ran, what they tried, and how heavy the model calls were."

      link :runs,
           text: "Runs",
           url: ->(context) { context.admin_screen_path("agent_runs") },
           style: :primary
      link :tasks,
           text: "Tasks",
           url: ->(context) { context.admin_screen_path("agent_tasks") }
      link :usage,
           text: "Usage by agent",
           url: ->(context) { context.admin_screen_path("agent_usage") }
      link :evaluations,
           text: "Evaluations",
           url: ->(context) { context.admin_screen_path("agent_evaluations") }

      widget "widgets.agents.failed_runs"
      widget "widgets.agents.attempts_this_period"
      widget "widgets.agents.tokens_this_period"
      widget "widgets.agents.hungry_agents"
    end
  end
end
