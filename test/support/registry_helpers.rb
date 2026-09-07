# frozen_string_literal: true

module RegistryHelpers
  def setup
    super if defined?(super)
    RecordingStudioAgents.reset!
    RecordingStudioAI.instance_variable_set(:@tools, RecordingStudioAI::Tools::Registry.new)
  end

  def register_ai_tool(key, version: 1, **overrides)
    attributes = {
      key: key,
      version: version,
      name: key.to_s.tr("_", " "),
      description: "Test tool",
      use_when: "tests",
      do_not_use_when: "production",
      parameters: [],
      returns: "ok",
      cost: :low,
      latency: :fast,
      read_only: true,
      destructive: false,
      requires_confirmation: false,
      idempotent: true,
      executor_label: "Test",
      executor: ->(arguments, _context) { arguments }
    }.merge(overrides)
    RecordingStudioAI.tools.register(**attributes)
  end

  def register_librarian(handoffs: {}, tools: { find_page: 1 })
    register_ai_tool(:find_page)
    RecordingStudioAgents.skills.register(
      key: :lookup,
      version: 1,
      name: "Lookup",
      description: "Find pages",
      instructions: "Use find_page.",
      required_tools: { find_page: 1 }
    )
    RecordingStudioAgents.agents.register(
      key: :librarian,
      version: 1,
      name: "Librarian",
      description: "Finds pages",
      instructions: "Find the named page.",
      skills: { lookup: 1 },
      tools: tools,
      handoffs: handoffs
    )
  end
end
