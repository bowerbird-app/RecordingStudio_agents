# frozen_string_literal: true

require_relative "admin/last_four_weeks_period"
require_relative "admin/flatpack_button_url"
require_relative "admin/queries"
require_relative "admin/section"
require_relative "admin/agents_screen"
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

      align_last_four_weeks_period!
      align_flatpack_button_url!
      RecordingStudioAdmin.register_section(Section)
      register_screens!
      register_widgets!
    end

    def registered?
      return false unless defined?(::RecordingStudioAdmin)

      RecordingStudioAdmin.section_for("agents").present?
    end

    def align_last_four_weeks_period!
      return unless defined?(::RecordingStudioAdmin::Period)

      singleton = ::RecordingStudioAdmin::Period.singleton_class
      return if singleton.ancestors.include?(LastFourWeeksPeriod)

      singleton.prepend(LastFourWeeksPeriod)
    end
    private_class_method :align_last_four_weeks_period!

    def align_flatpack_button_url!
      return unless defined?(::FlatPack::Button::Component)

      target = ::FlatPack::Button::Component
      return if target.ancestors.include?(FlatpackButtonUrl)

      target.prepend(FlatpackButtonUrl)
    end
    private_class_method :align_flatpack_button_url!

    def register_screens!
      [
        AgentsScreen,
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
