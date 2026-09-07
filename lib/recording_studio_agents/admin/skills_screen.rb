# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    class SkillsScreen < RecordingStudioAdmin::Screen
      key "registered_skills"
      icon :book_open
      title "Skills"
      subtitle "Instructions other gems contribute."

      query do |_context|
        Queries.skills
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
