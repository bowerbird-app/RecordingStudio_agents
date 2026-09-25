# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class RunsScreen < RecordingStudioAdmin::Screen
      key "agent_runs"
      icon :play
      title "Runs"
      subtitle "One attempt each. Steps lists the work in order."

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
        column :agent_key,
               title: "Agent",
               value: ->(row, context) { Queries.agent_name_cell(row, context) }
        column :agent_version, title: "Version"
        column :status,
               title: "Status",
               display: :badge,
               display_options: ->(_row, _context, value) { Queries.status_badge_options(value) }
        column :extra_skills, title: "Extra skills",
                              value: ->(row, _context) { row.selected_skill_labels.presence || "None" }
        column :steps, title: "Steps", sortable: false,
                       value: ->(row, _context) { Progress.for(row).map(&:label).join(", ").presence || "None" }
        column :tokens, title: "Tokens", sortable: false,
                        header_tooltip: "Tokens across this attempt's model calls. A dash means that history was cleaned.",
                        value: lambda { |row, _context|
                          Queries.format_tokens(Queries.token_total(row))
                        }
        column :objective, title: "Now", sortable: false,
                           value: ->(row, _context) { Queries.objective_cell(row) }
        column :plans, title: "Plans", sortable: false,
                       header_tooltip: "How many times this attempt wrote or rewrote a plan.",
                       value: ->(row, _context) { Queries.counter_cell(row, "reasoner_calls") }
        column :check_ins, title: "Check-ins", sortable: false,
                           header_tooltip: "How many times the cheap checker looked at the work.",
                           value: ->(row, _context) { Queries.counter_cell(row, "controller_calls") }
        column :replans, title: "New plans", sortable: false,
                         value: ->(row, _context) { Queries.counter_cell(row, "replans") }
        column :stuck, title: "Stuck", sortable: false,
                       value: ->(row, _context) { Queries.stuck_cell(row) }
        column :tools, title: "Tools", sortable: false,
                       header_tooltip: "Tools this attempt has run.",
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
