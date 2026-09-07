# frozen_string_literal: true

require_relative "admin/queries"
require_relative "admin/section"
require_relative "admin/agents_screen"
require_relative "admin/skills_screen"
require_relative "admin/skill_packs_screen"
require_relative "admin/tasks_screen"
require_relative "admin/runs_screen"
require_relative "admin/usage_screen"
require_relative "admin/evaluations_screen"
require_relative "admin/widgets"

module RecordingStudioAgents
  module Admin
    module_function

    def register!
      return unless defined?(::RecordingStudioAdmin)

      RecordingStudioAdmin.register_section(Section)
      RecordingStudioAdmin.register_screen(AgentsScreen)
      RecordingStudioAdmin.register_screen(SkillsScreen)
      RecordingStudioAdmin.register_screen(SkillPacksScreen)
      RecordingStudioAdmin.register_screen(TasksScreen)
      RecordingStudioAdmin.register_screen(RunsScreen)
      RecordingStudioAdmin.register_screen(UsageScreen)
      RecordingStudioAdmin.register_screen(EvaluationsScreen)
      RecordingStudioAdmin.register_widget(Widgets::FAILED_RUNS)
      RecordingStudioAdmin.register_widget(Widgets::ATTEMPTS_THIS_PERIOD)
      RecordingStudioAdmin.register_widget(Widgets::TOKENS_THIS_PERIOD)
      RecordingStudioAdmin.register_widget(Widgets::HUNGRY_AGENTS)
    end

    def registered?
      return false unless defined?(::RecordingStudioAdmin)

      RecordingStudioAdmin.section_for("agents").present?
    end
  end
end
