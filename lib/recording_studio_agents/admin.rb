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
      register_screens!
      register_widgets!
    end

    def registered?
      return false unless defined?(::RecordingStudioAdmin)

      RecordingStudioAdmin.section_for("agents").present?
    end

    def register_screens!
      [
        AgentsScreen,
        SkillsScreen,
        SkillPacksScreen,
        TasksScreen,
        RunsScreen,
        UsageScreen,
        EvaluationsScreen
      ].each { |screen| RecordingStudioAdmin.register_screen(screen) }
    end
    private_class_method :register_screens!

    def register_widgets!
      [
        Widgets::FAILED_RUNS,
        Widgets::ATTEMPTS_THIS_PERIOD,
        Widgets::TOKENS_THIS_PERIOD,
        Widgets::HUNGRY_AGENTS
      ].each { |widget| RecordingStudioAdmin.register_widget(widget) }
    end
    private_class_method :register_widgets!
  end
end
