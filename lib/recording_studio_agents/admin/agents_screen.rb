# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class AgentsScreen < RecordingStudioAdmin::Screen
      key "registered_agents"
      icon :sparkles
      title "Agent list"
      subtitle "Including agents that have not run yet."

      query do |_context|
        Queries.agents
      end

      table do
        title " "
        hide_count
        column :key, title: "Key", value: ->(row, _context) { row.key }
        column :version, title: "Version", value: ->(row, _context) { row.version }
        column :name, title: "Name", value: ->(row, _context) { row.name }
        column :enabled, title: "Enabled", value: ->(row, _context) { row.enabled ? "Yes" : "No" }
      end
    end
  end
end
