# frozen_string_literal: true

RecordingStudioAI.tools.register(
  override: true,
  key: :find_page,
  version: 1,
  name: "Find page",
  description: "Find a page by title inside the current workspace.",
  use_when: "The task names a page to locate.",
  do_not_use_when: "The task asks to change a page.",
  parameters: [
    {
      name: "title",
      type: "string",
      required: true,
      description: "Exact page title to find."
    }
  ],
  returns: "The page title and whether it was found.",
  cost: :low,
  latency: :fast,
  read_only: true,
  destructive: false,
  requires_confirmation: false,
  idempotent: true,
  executor_label: "Dummy::FindPage",
  executor: lambda do |arguments, context|
    title = arguments.fetch("title")
    page = Page.find_by(title: title)
    recording = page && RecordingStudio::Recording.find_by(
      recordable: page,
      root_recording_id: context.root_recording.id,
      trashed_at: nil
    )
    { "found" => recording.present?, "title" => title, "page_recording_id" => recording&.id }
  end
)

RecordingStudioAI.tools.register(
  override: true,
  key: :retitle_page,
  version: 1,
  name: "Retitle page",
  description: "Change a page title after confirmation.",
  use_when: "The task asks to rename a page.",
  do_not_use_when: "The task only asks to find a page.",
  parameters: [
    {
      name: "page_recording_id",
      type: "string",
      required: true,
      description: "The page to retitle."
    },
    {
      name: "title",
      type: "string",
      required: true,
      description: "The new title."
    }
  ],
  returns: "The updated title.",
  cost: :low,
  latency: :fast,
  read_only: false,
  destructive: false,
  requires_confirmation: true,
  idempotent: true,
  executor_label: "Dummy::RetitlePage",
  executor: lambda do |arguments, context|
    recording = RecordingStudio::Recording.find(arguments.fetch("page_recording_id"))
    unless recording.root_recording_id == context.root_recording.id
      raise ArgumentError, "page is outside this workspace"
    end

    previous = Current.actor
    Current.actor = context.initiator
    recording.root_recording.revise(recording) do |page|
      page.title = arguments.fetch("title")
    end
    { "title" => arguments.fetch("title") }
  ensure
    Current.actor = previous
  end
)

RecordingStudioAgents.knowledge.register(
  key: :workspace_outline,
  version: 1,
  name: "Workspace outline",
  description: "Folders and pages in the current workspace.",
  loader: lambda do |context|
    recordings = RecordingStudio::Recording.where(
      root_recording_id: context.root_recording.id,
      trashed_at: nil
    ).includes(:recordable)
    lines = recordings.map do |recording|
      recordable = recording.recordable
      label = recordable.try(:title) || recordable.try(:name) || recording.recordable_type
      "#{recording.recordable_type}: #{label}"
    end
    [
      RecordingStudioAgents::Knowledge::Entry.new(
        key: "workspace_outline",
        title: "Workspace outline",
        content: lines.join("\n"),
        source_recording: context.root_recording
      )
    ]
  end
)

RecordingStudioAgents.skills.register(
  key: :page_lookup,
  version: 1,
  name: "Page lookup",
  description: "Find a named page and stop.",
  instructions: <<~TEXT,
    Use the find page tool when the task names a page.
    Quote the title you found.
    Request a handoff only when the page is missing and a reviewer should decide next.
  TEXT
  required_tools: { find_page: 1 }
)

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
  key: :page_reviewer,
  version: 1,
  name: "Page reviewer",
  description: "Reviews a missing-page case.",
  instructions: "Say what is missing and stop.",
  knowledge: { workspace_outline: 1 },
  enabled: true
)

RecordingStudioAgents.agents.register(
  key: :page_librarian,
  version: 1,
  name: "Page librarian",
  description: "Finds a page in the current workspace.",
  instructions: "Find the named page with the allowed tool. Request a review handoff if it is missing.",
  skills: { page_lookup: 1 },
  tools: { find_page: 1, retitle_page: 1 },
  knowledge: { workspace_outline: 1 },
  handoffs: { page_reviewer: 1 },
  enabled: true
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
  enabled: true
)
