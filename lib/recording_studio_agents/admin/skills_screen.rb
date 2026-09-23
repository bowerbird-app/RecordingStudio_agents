# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class SkillsScreen < RecordingStudioAdmin::Screen
      key "registered_skills"
      icon :sparkles
      title "Skills"
      subtitle "Procedures agents can follow."

      query do |_context|
        Queries.skills
      end

      table do
        title " "
        hide_count
        column :name, title: "Name", value: ->(row, context) { Queries.skill_name_cell(row, context) }
        column :version, title: "Version", value: ->(row, _context) { row.version }
        column :key, title: "Key", value: ->(row, _context) { row.key }
        default_columns :name, :version
      end
    end
  end
end
