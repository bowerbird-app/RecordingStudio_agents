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

  def register_support_clerk
    register_ai_tool(:lookup_invoice)
    RecordingStudioAgents.skills.register(
      key: :support_voice,
      version: 1,
      name: "Support voice",
      description: "How to talk on a support ticket.",
      instructions: "Keep a steady voice and ask one question at a time.",
      use_when: "Every support ticket.",
      do_not_use_when: "The work is not a support ticket."
    )
    RecordingStudioAgents.skills.register(
      key: :billing_help,
      version: 1,
      name: "Billing help",
      description: "Refunds and invoices.",
      instructions: "Explain the refund window and look up the invoice before you promise anything.",
      required_tools: { lookup_invoice: 1 },
      use_when: "The ticket is about a charge or refund.",
      do_not_use_when: "The ticket is about signing in."
    )
    RecordingStudioAgents.skills.register(
      key: :login_help,
      version: 1,
      name: "Login help",
      description: "People who cannot sign in.",
      instructions: "Never ask for a password. Send a reset link instead.",
      use_when: "The person cannot sign in.",
      do_not_use_when: "The ticket is about billing."
    )
    RecordingStudioAgents.skill_packs.register(
      key: :billing_tickets,
      version: 1,
      name: "Billing tickets",
      description: "Refund and invoice questions.",
      skills: { billing_help: 1 }
    )
    RecordingStudioAgents.agents.register(
      key: :support_clerk,
      version: 1,
      name: "Support clerk",
      description: "Handles a support ticket with only the skills that ticket needs.",
      instructions: "Answer the ticket. Load extra help only when the host selected it.",
      skills: { support_voice: 1 },
      optional_skills: { billing_help: 1, login_help: 1 },
      packs: { billing_tickets: 1 },
      tools: { lookup_invoice: 1 }
    )
  end
end
