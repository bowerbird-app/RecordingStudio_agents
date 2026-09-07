# Recording Studio Agents

Recording Studio Agents defines reusable agents in code and records each task attempt as an `AgentRun`. An agent compiles exact versions of its skills, tools, knowledge sources, and allowed handoff targets into one immutable program. `Agent#run` validates the task, authorizes the actor through Recording Studio AI, creates or reuses the run, and executes through `RecordingStudioAI.generate`.

Agents does not add a second authorization callback. Configure Recording Studio AI with its Accessible adapter.

```ruby
RecordingStudioAI.configure do |config|
  config.authorization_handler =
    RecordingStudioAI::AccessibleAuthorization.method(:call)
end
```

## Conceptual model

An **agent** is a reusable definition. It is not an execution and it does not own a schedule.

A **skill** is versioned procedure text. Other gems register skills. A skill can name the tools it needs. It does not grant those tools to an agent. Required skills always compile. Optional skills compile only when a run selects a pack or extra skills.

A **skill pack** is a named bundle of optional skills. Pack skills must already be on the agent's optional allowlist.

A **tool** is an executable capability registered with Recording Studio AI. Agents never grows a parallel tool system.

**Knowledge** is application data loaded at run time. Loaders return typed entries. Agents authorizes the run before it invokes a loader. Gathered entries are capped at 5 seconds, 40 entries, and 32KB. When an entry cites a source recording, it must stay inside the task root.

A **task** is a durable goal inside a workspace, identified by a stable key.

An **agent run** is one attempt. It stores status, an optional output digest, and the Recording Studio AI run id. It does not copy prompts, model output, or chain-of-thought. Duplicate delivery of the same `idempotency_key` reuses that attempt.

A **handoff** is an allowlisted request recorded by an internal AI tool. `Agent#run` never starts the target. The host routes the next call.

`enabled` is a registry boolean. Lookup for a disabled agent raises `AgentDisabled`. Admin still lists disabled agents.

## Install

Add the gem, then copy and run the engine migrations.

```sh
bin/rails generate recording_studio_agents:install
bin/rails generate recording_studio_agents:migrations
bin/rails db:migrate
```

Register the `agents` section on an admin root and mount Recording Studio Admin.

```ruby
recording_studio_admin_for :admin, at: "/admin", root_section: :agents
```

## Register a skill and a tool

Tools belong to Recording Studio AI. A skill names the tools it needs, but the agent must also allow them.

```ruby
RecordingStudioAI.tools.register(
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
  returns: "Whether the page was found.",
  cost: :low,
  latency: :fast,
  read_only: true,
  destructive: false,
  requires_confirmation: false,
  idempotent: true,
  executor_label: "FindPage",
  executor: FindPage.method(:call)
)

RecordingStudioAgents.skills.register(
  key: :page_lookup,
  version: 1,
  name: "Page lookup",
  description: "Find a named page and stop.",
  instructions: <<~TEXT,
    Use the find page tool when the task names a page.
    Quote the title you found.
  TEXT
  required_tools: { find_page: 1 }
)
```

Registration rejects a duplicate key and version. Boot and `agent()` raise when a required tool is missing from the agent allowlist or from Recording Studio AI.

## Define agents and knowledge in the host

```ruby
RecordingStudioAgents.knowledge.register(
  key: :workspace_outline,
  version: 1,
  name: "Workspace outline",
  description: "Folders and pages in the current workspace.",
  loader: lambda do |context|
    [
      RecordingStudioAgents::Knowledge::Entry.new(
        key: "workspace_outline",
        title: "Workspace outline",
        content: WorkspaceOutline.call(context.root_recording),
        source_recording: context.root_recording
      )
    ]
  end
)

RecordingStudioAgents.agents.register(
  key: :page_librarian,
  version: 1,
  name: "Page librarian",
  description: "Finds a page in the current workspace.",
  instructions: "Find the named page with the allowed tool.",
  skills: { page_lookup: 1 },
  tools: { find_page: 1 },
  knowledge: { workspace_outline: 1 },
  handoffs: { page_reviewer: 1 },
  enabled: true
)
```

All references pin an exact positive integer version.

## Optional skills and packs

`skills:` always compile into the program. `optional_skills:` is an allowlist. A run loads those skills only when the host passes `pack:` or `extra_skills:`.

A **skill pack** groups optional skills. Pack skills must already be listed on `optional_skills:`. The agent lists the packs it allows. `pack: :billing_tickets` uses that listed version. A one-key hash such as `{ billing_tickets: 1 }` also works.

`agent()` returns a definition handle. The program compiles at `run`, so the digest includes the selected set. Reusing an `idempotency_key` with a different pack raises `IdempotencyConflict`.

Skills may set `use_when` and `do_not_use_when` for host catalogs. Those strings are not added to a generate prompt unless the skill is selected.

Tools named only by an unselected optional skill are dropped from that generate call. They still belong on the agent allowlist and in Recording Studio AI.

```ruby
RecordingStudioAgents.skill_packs.register(
  key: :billing_tickets,
  version: 1,
  name: "Billing tickets",
  description: "Refund and invoice questions.",
  skills: { refund_policy: 1, invoice_lookup: 1 }
)

RecordingStudioAgents.agents.register(
  key: :support,
  version: 1,
  name: "Support",
  description: "Handles a support ticket.",
  instructions: "Answer the ticket with the loaded skills.",
  skills: { support_voice: 1 },
  optional_skills: { refund_policy: 1, invoice_lookup: 1, access_reset: 1 },
  packs: { billing_tickets: 1 },
  tools: { lookup_invoice: 1 }
)

RecordingStudioAgents.agent(:support, version: 1).run(
  task: task,
  root_recording: root,
  initiator: user,
  initiator_kind: :user,
  execution_source: :job,
  idempotency_key: job_id,
  pack: :billing_tickets
)
```

`extra_skills: { access_reset: 1 }` can load optional skills without a pack, and can combine with `pack:`.

## Execute a task from a job

A task key identifies one durable goal inside a workspace. An idempotency key identifies one attempt. Use the Active Job `job_id` as that attempt key so retries and duplicate delivery converge on the same `AgentRun`.

```ruby
class FindPageJob < ApplicationJob
  def perform(root_recording_id:, user_id:)
    root = RecordingStudio::Recording.find(root_recording_id)
    user = User.find(user_id)

    task = RecordingStudioAgents::TaskInput.new(
      key: "find_page:#{root.id}",
      goal: "Find the Getting Started page.",
      context: {}
    )

    result = RecordingStudioAgents.agent(:page_librarian, version: 1).run(
      task: task,
      root_recording: root,
      initiator: user,
      initiator_kind: :user,
      execution_source: :job,
      idempotency_key: job_id
    )

    case result
    when RecordingStudioAgents::Results::Completed
      Rails.logger.info("agent_run=#{result.run.id} completed")
    when RecordingStudioAgents::Results::HandoffRequested
      HandoffRouterJob.perform_later(
        target_agent_key: result.request.target.key,
        target_agent_version: result.request.target.version,
        task_id: result.run.task_id,
        requested_by_run_id: result.run.id
      )
    when RecordingStudioAgents::Results::Blocked
      result
    when RecordingStudioAgents::Results::Failed
      raise RecordingStudioAgents::ExecutionFailed.new(result) if result.failure.retryable?
    when RecordingStudioAgents::Results::Existing,
         RecordingStudioAgents::Results::InProgress
      result
    end
  end
end
```

`Results::Completed` carries in-memory output for the call that ran. Replay returns `Results::Existing`. `Results::Blocked` means a tool is waiting on Recording Studio AI confirmation. Call `run` again with the same idempotency key after the host confirms.

## Progress

`RecordingStudioAgents::Progress.for(run)` returns coarse steps for one attempt. Steps come from knowledge load plus Recording Studio AI tool invocations, joined by `recording_studio_ai_run_id` or `request_id` (`recording-studio-agents:<agent_run_id>`). Hosts can poll that helper from a job. Do not stream token text as progress, and do not copy model output onto the agent run.

Each step has a label and a badge: Done, Working, Waiting, or Failed. Tool labels use the tool name (for example "Find page"), not the registry key. The dummy home lists steps after a librarian run. Admin run rows show the labels in a Steps column.

## Admin

The `agents` section lists code-defined agents, skills, and skill packs as read-only catalogs. It lists tasks, runs, and evaluations from the engine tables. Run rows show which extra skills were loaded, a compact Steps column, and a link to the associated Recording Studio AI execution. Admin never displays chain-of-thought.

Hosts that use importmap must pin Recording Studio Admin controllers so screen tables load:

```ruby
pin_all_from RecordingStudioAdmin::Engine.root.join("app/javascript/recording_studio_admin/controllers"),
             under: "controllers/recording_studio_admin",
             to: "recording_studio_admin/controllers",
             preload: false
```

## Dummy app

`test/dummy` is a host that proves the gem. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. The home page runs the page librarian over Workspace, Folder, and Page, then lists what it did. A support clerk is registered for optional-skill tests and does not appear as a second home action. `/admin` is Recording Studio Admin with the agents section. Tests do not call a live model provider.
