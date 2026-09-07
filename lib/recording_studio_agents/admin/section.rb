# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class Section < RecordingStudioAdmin::Section
      key "agents"
      icon :sparkles
      title "Agents"
      subtitle "Who ran, what they tried, and what failed."

      link :agents,
           text: "Agents",
           url: ->(context) { context.admin_screen_path("registered_agents") },
           style: :primary
      link :skills,
           text: "Skills",
           url: ->(context) { context.admin_screen_path("registered_skills") }
      link :skill_packs,
           text: "Skill packs",
           url: ->(context) { context.admin_screen_path("registered_skill_packs") }
      link :tasks,
           text: "Tasks",
           url: ->(context) { context.admin_screen_path("agent_tasks") }
      link :runs,
           text: "Runs",
           url: ->(context) { context.admin_screen_path("agent_runs") }
      link :evaluations,
           text: "Evaluations",
           url: ->(context) { context.admin_screen_path("agent_evaluations") }

      widget "widgets.agents.failed_runs"
      widget "widgets.agents.run_count"
    end
  end
end
