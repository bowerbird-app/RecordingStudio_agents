# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class UsageScreen < RecordingStudioAdmin::Screen
      key "agent_usage"
      icon :chart_bar
      title "By agent"
      subtitle "Averages skip attempts whose model call is gone."

      query do |context|
        Queries.by_agent_rows(
          root_ids: Queries.visible_root_ids(context),
          range: Queries.selected_time_range(context, screen: self)
        )
      end

      filter_presentation :modal, inline_count: 1
      filter :date_range, field: :created_at, default: :last_4_weeks

      summary do
        hide_change
        label "Agents"
      end

      table do
        title " "
        hide_columns_button
        column :agent_key,
               title: "Agent",
               sortable: false,
               header_tooltip: "The agent key from the attempt.",
               value: lambda { |row, context|
                 ActionController::Base.helpers.link_to(
                   row.agent_key,
                   Queries.screen_href(context, "agent_runs", agent_key: row.agent_key),
                   class: "text-(--color-primary-background-color)",
                   data: { turbo_frame: "_top" }
                 )
               }
        column :agent_version, title: "Version", sortable: false
        column :attempts, title: "Attempts", sortable: false
        column :succeeded, title: "Succeeded", sortable: false
        column :failed, title: "Failed", sortable: false
        column :waiting, title: "Waiting", sortable: false
        column :avg_tokens,
               title: "Avg tokens",
               sortable: false,
               header_tooltip: "Mean model-call tokens. Attempts with no AI row are skipped.",
               value: ->(row, _context) { Queries.format_tokens(row.avg_tokens) }
        column :avg_latency_ms,
               title: "Avg wait (ms)",
               sortable: false,
               header_tooltip: "Mean model-call wait. Attempts with no AI row are skipped.",
               value: ->(row, _context) { Queries.format_tokens(row.avg_latency_ms) }
        column :avg_tools,
               title: "Avg tools",
               sortable: false,
               header_tooltip: "Mean custom tool calls. Attempts with no AI row are skipped.",
               value: ->(row, _context) { Queries.format_tools(row.avg_tools) }
        paginate per_page: 25
      end
    end
  end
end
