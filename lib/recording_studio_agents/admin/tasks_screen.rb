# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class TasksScreen < RecordingStudioAdmin::Screen
      key "agent_tasks"
      icon :clipboard_document_list
      title "Tasks"
      subtitle "Goals given to an agent."

      query do |context|
        Queries.tasks(context: context)
      end

      table do
        title " "
        column :goal, title: "Goal"
        column :created_at, title: "Created"
        paginate per_page: 25
        default_sort :created_at, direction: :desc
      end
    end
  end
end
