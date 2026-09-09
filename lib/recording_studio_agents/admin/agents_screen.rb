# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class AgentsScreen < RecordingStudioAdmin::Screen
      key "registered_agents"
      icon :sparkles
      title "Agents"
      subtitle "Including agents that have not run yet."

      query do |_context|
        Queries.agents
      end

      table do
        title " "
        hide_count
        column :name, title: "Name", value: ->(row, context) { Queries.agent_name_cell(row, context) }
        column :version, title: "Version", value: ->(row, _context) { row.version }
        column :enabled,
               title: "Enabled",
               display: :badge,
               display_options: ->(_row, _context, value) { Queries.enabled_badge_options(value) }
        column :key, title: "Key", value: ->(row, _context) { row.key }
        default_columns :name, :version, :enabled
      end
    end
  end
end
