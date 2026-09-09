# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class SkillShowScreen < RecordingStudioAdmin::Screen
      key "registered_skill"
      icon :sparkles
      title { |context| Queries.skill_show_title(context) }
      subtitle { |context| Queries.skill_show_subtitle(context) }

      query do |context|
        Queries.skill_detail_rows(Queries.selected_skill(context), context)
      end

      table do
        title " "
        hide_columns_button
        hide_count
        column :label, title: "Detail", sortable: false
        column :value, title: "Value", sortable: false
        default_columns :label, :value
      end
    end
  end
end
