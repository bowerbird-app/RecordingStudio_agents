# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class EvaluationsScreen < RecordingStudioAdmin::Screen
      key "agent_evaluations"
      icon :check_badge
      title "Evaluations"
      subtitle "Pass, fail, or still deciding."

      query do |context|
        Queries.evaluations(context: context)
      end

      table do
        title " "
        column :evaluator_key, title: "Evaluator"
        column :verdict, title: "Verdict"
        column :score, title: "Score"
        column :created_at, title: "Created"
        paginate per_page: 25
        default_sort :created_at, direction: :desc
      end
    end
  end
end
