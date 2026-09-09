# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class ToolShowScreen < RecordingStudioAdmin::Screen
      key "registered_tool"
      icon :wrench_screwdriver
      title { |context| Queries.tool_show_title(context) }
      subtitle { |context| Queries.tool_show_subtitle(context) }

      button :calls,
             text: "Calls",
             url: lambda { |context|
               Queries.screen_href(context, "tool_calls", tool_key: Queries.selected_tool_key(context))
             },
             visible_if: ->(context) { Queries.selected_tool_key(context).present? }

      query do |context|
        Queries.tool_detail_rows(Queries.selected_tool(context))
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
