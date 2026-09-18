# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class AgentsResource < RecordingStudioAdmin::Resource
      key "registered_agents"
      section "agents"
      icon :sparkles
      title "Agents"
      subtitle "Turn an agent on or off."

      action :turn_off,
             text: "Turn off",
             icon: "pause",
             method: :post,
             confirm: ->(row, _context) { "Turn off #{row.name}?" },
             url: ->(row, context) { Queries.agent_enablement_href(row, :turn_off, context) },
             visible_if: ->(row, _context) { Enablement.enabled?(row) }

      action :turn_on,
             text: "Turn on",
             icon: "play",
             method: :post,
             confirm: ->(row, _context) { "Turn on #{row.name}?" },
             url: ->(row, context) { Queries.agent_enablement_href(row, :turn_on, context) },
             visible_if: ->(row, _context) { !Enablement.enabled?(row) }
    end
  end
end
