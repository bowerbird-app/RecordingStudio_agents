# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class RunsScreen < RecordingStudioAdmin::Screen
      key "agent_runs"
      icon :play
      title "Runs"
      subtitle "One attempt each. Tokens and tools come from the linked model call."

      query do |context|
        Queries.runs(context: context)
      end

      filter_presentation :modal, inline_count: 3
      filter :date_range, field: :created_at, default: :last_4_weeks
      filter :group_by, values: %i[hour day week month year], default: :day
      filter :agent_key,
             title: "Agent",
             field: :agent_key,
             values: -> { Queries.distinct_agent_keys }
      filter :status,
             field: :status,
             values: -> { AgentRun::STATUSES }

      summary do
        change_good_when :neutral
      end

      chart do
        title "Attempts"
        subtitle "How many attempts landed over time."
        type :line
        series do |context|
          [{
            name: "Attempts",
            data: RecordingStudioAdmin::AdminActivityLogsSupport.date_series(
              context.query_result.relation.reorder(nil),
              field: "recording_studio_agents_agent_runs.created_at",
              bucket: context.filter_value(:group_by) || :day
            )
          }]
        end
        options do
          {
            height: 300,
            stroke: { curve: "smooth", width: 3 },
            xaxis: {
              labels: { show: true },
              axisBorder: { show: false },
              axisTicks: { show: false }
            },
            yaxis: { min: 0 },
            grid: { xaxis: { lines: { show: false } } }
          }
        end
      end

      table do
        title " "
        show_columns_button
        column :agent_key, title: "Agent"
        column :agent_version, title: "Version"
        column :status, title: "Status"
        column :extra_skills, title: "Extra skills",
                              value: ->(row, _context) { row.selected_skill_labels.presence || "None" }
        column :steps, title: "Steps", sortable: false,
                       value: ->(row, _context) { Progress.for(row).map(&:label).join(", ").presence || "None" }
        column :tokens, title: "Tokens", sortable: false,
                        header_tooltip: "Tokens on the linked model call. A dash means that history was cleaned.",
                        value: lambda { |row, _context|
                          Queries.format_tokens(Queries.ai_run_for(row.recording_studio_ai_run_id)&.total_tokens)
                        }
        column :tools, title: "Tools", sortable: false,
                       header_tooltip: "Custom tools on the linked model call.",
                       value: ->(row, context) { Queries.tools_cell(row, context) }
        column :idempotency_key, title: "Attempt key"
        column :recording_studio_ai_run_id, title: "AI run", sortable: false,
                                            value: ->(row, context) { Queries.ai_run_cell(row, context) }
        column :created_at, title: "Created"
        default_columns :agent_key, :status, :steps, :tokens, :tools, :recording_studio_ai_run_id, :created_at
        paginate per_page: 25
        default_sort :created_at, direction: :desc
      end
    end
  end
end
