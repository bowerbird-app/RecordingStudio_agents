# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class RunsScreen < RecordingStudioAdmin::Screen
      key "agent_runs"
      icon :play
      title "Runs"
      subtitle "One attempt each. Open Recording Studio AI for the model call."

      query do |context|
        Queries.runs(context: context)
      end

      table do
        title " "
        column :agent_key, title: "Agent"
        column :agent_version, title: "Version"
        column :status, title: "Status"
        column :extra_skills, title: "Extra skills",
                              value: ->(row, _context) { row.selected_skill_labels.presence || "None" }
        column :idempotency_key, title: "Attempt key"
        column :recording_studio_ai_run_id, title: "AI run"
        column :created_at, title: "Created"
        paginate per_page: 25
        default_sort :created_at, direction: :desc
      end
    end
  end
end
