# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    module Widgets
      FAILED_RUNS = RecordingStudioAdmin::Widget.new("widgets.agents.failed_runs") do
        type :list
        title "Failed runs"
        info "The last attempts that did not finish. Open Runs if you need to retry from the host."
        hide_change
        hide_period
        items do |context|
          Queries.recent_failed_runs(context: context).map do |run|
            {
              text: "#{run.agent_key} · #{run.failure_code || 'failed'}",
              href: Queries.screen_href(context, "agent_runs", status: "failed")
            }
          end
        end
      end

      ATTEMPTS_THIS_PERIOD = RecordingStudioAdmin::Widget.new("widgets.agents.attempts_this_period") do
        type :number
        title "Attempts this period"
        info "How many times an agent started in the last 30 days, versus the 30 before that."
        metadata { { period_label: "Last 30 days" } }
        value do |context|
          root_ids = Queries.visible_root_ids(context)
          Queries.delimited_number(
            Queries.attempts_in_period(root_ids: root_ids, range: Queries.current_period)
          )
        end
        change do |context|
          root_ids = Queries.visible_root_ids(context)
          Queries.percentage_change_label(
            current: Queries.attempts_in_period(root_ids: root_ids, range: Queries.current_period),
            previous: Queries.attempts_in_period(root_ids: root_ids, range: Queries.previous_period)
          )
        end
        change_good_when :neutral
        link_to { |context| context.admin_screen_path("agent_runs") }
      end

      TOKENS_THIS_PERIOD = RecordingStudioAdmin::Widget.new("widgets.agents.tokens_this_period") do
        type :number
        title "Tokens this period"
        info "Model-call tokens for those attempts. Shows blank if AI history was cleaned."
        metadata { { period_label: "Last 30 days" } }
        value do |context|
          root_ids = Queries.visible_root_ids(context)
          Queries.delimited_number(
            Queries.tokens_in_period(root_ids: root_ids, range: Queries.current_period)
          )
        end
        change do |context|
          root_ids = Queries.visible_root_ids(context)
          Queries.percentage_change_label(
            current: Queries.tokens_in_period(root_ids: root_ids, range: Queries.current_period),
            previous: Queries.tokens_in_period(root_ids: root_ids, range: Queries.previous_period)
          )
        end
        change_good_when :down
        link_to { |context| context.admin_screen_path("agent_usage") }
      end

      HUNGRY_AGENTS = RecordingStudioAdmin::Widget.new("widgets.agents.hungry_agents") do
        type :list
        title "Hungry agents"
        info "Who used the most model-call tokens in the last 30 days."
        hide_change
        metadata { { period_label: "Last 30 days" } }
        items do |context|
          root_ids = Queries.visible_root_ids(context)
          Queries.hungry_agents(root_ids: root_ids, range: Queries.current_period).map do |row|
            {
              text: Queries.hungry_label(agent_key: row[:agent_key], tokens: row[:tokens]),
              href: Queries.screen_href(context, "agent_runs", agent_key: row[:agent_key])
            }
          end
        end
      end
    end
  end
end
