# frozen_string_literal: true

module AdminScreens
  class RootSection < RecordingStudioAdmin::Section
    key "root"
    icon :building_office
    title "Staff"
    subtitle "Agents, runs, and model calls."

    link :agents,
         text: "Agents",
         url: ->(context) { context.admin_section_path("agents") },
         style: :secondary
    link :model_calls,
         text: "Model calls",
         url: ->(context) { context.admin_section_path("recording_studio_ai") },
         style: :secondary
  end
end
