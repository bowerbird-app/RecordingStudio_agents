# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class AgentShowScreen < RecordingStudioAdmin::Screen
      key "registered_agent"
      icon :sparkles
      title { |context| Queries.agent_show_title(context) }
      subtitle { |context| Queries.agent_show_subtitle(context) }

      button :runs,
             text: "Runs",
             url: lambda { |context|
               Queries.screen_href(context, "agent_runs", agent_key: Queries.selected_agent_key(context))
             },
             visible_if: ->(context) { Queries.selected_agent_key(context).present? }

      query do |context|
        Queries.agent_detail_rows(Queries.selected_agent(context), context)
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
