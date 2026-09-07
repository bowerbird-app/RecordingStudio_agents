# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class SkillPacksScreen < RecordingStudioAdmin::Screen
      key "registered_skill_packs"
      icon :queue_list
      title "Skill packs"
      subtitle "Optional bundles you can load for a ticket."

      query do |_context|
        Queries.skill_packs
      end

      table do
        title " "
        hide_count
        column :key, title: "Key", value: ->(row, _context) { row.key }
        column :version, title: "Version", value: ->(row, _context) { row.version }
        column :name, title: "Name", value: ->(row, _context) { row.name }
      end
    end
  end
end
