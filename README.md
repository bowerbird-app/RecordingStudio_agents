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

**Knowledge** is application data loaded at run time. Loaders return typed entries. Each entry must cite a source recording inside the task root. Agents authorizes the run before it invokes a loader. Gathered entries are capped at 5 seconds, 40 entries, and 32KB.

A **task** is a durable goal inside a workspace, identified by a stable key. `TaskInput#context` travels with the goal in the prompt, under a label that it is data. Empty context is omitted. It is not stored on the task, and it is not mixed into workspace knowledge. When `Agent#run` is given a `context_recording`, that recording must be the task root or a child inside that root.

An **agent run** is one attempt. It stores status, an optional output digest, the handoff allowlist from the program that started it, and the Recording Studio AI run id. It does not copy prompts, model output, or chain-of-thought. Duplicate delivery of the same `idempotency_key` reuses that attempt. A different task or a different context recording for that key raises `IdempotencyConflict`.

A **handoff** is an allowlisted request recorded by an internal AI tool. The allowlist is the one stored on that run, not a fresh compile of the agent. The tool needs the live lease from that generate call, so a stale worker cannot stamp a target onto a run another worker owns. `Agent#run` never starts the target. The host routes the next call. If a worker dies after recording the target, a retry with the same idempotency key finishes as `handoff_requested` instead of succeeding.

`enabled` is a registry boolean. Lookup for a disabled agent raises `AgentDisabled`. Admin still lists disabled agents and can turn them on or off. An admin change is stored and wins over the registry default until it is changed again.

## Install

Add the gem, then copy and run the engine migrations.

```sh
bin/rails generate recording_studio_agents:install
bin/rails generate recording_studio_agents:migrations
bin/rails db:migrate
```

Register a staff hub and the `agents` section on an admin root, then mount Recording Studio Admin. The hub is `/admin`. Agents opens at `/admin/sections/agents`.

```ruby
recording_studio_admin_for :admin, at: "/admin", root_section: :root

recording_studio_admin_sections do
  section :root
  section :agents
end
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

`skills:` replaces that selection for one run, including the agent's required skills. Pass a hash of registered skills, or `{}` for no skill blocks. It cannot be combined with `pack:` or `extra_skills:`. `tools:` narrows the generate call to a subset of the agent's tools. Omit it to keep the usual allowlist. A skill on that run still needs its required tools in the subset, and a tool the agent does not list is rejected.

## Profile

A profile is the cost and quality tier for the generate call: `low`, `medium`, or `high`. Recording Studio AI maps each name to provider and model candidates. Agents does not name a model.

The host default is `RecordingStudioAgents.configuration.profile`, which starts at `:medium`. An agent can pin `profile:` when it is registered. `Agent#run` can pass `profile:` for that attempt. A run wins, then the agent, then the host default. A replay of the same idempotency key keeps the call that already started.

```ruby
RecordingStudioAgents.configure do |config|
  config.profile = :medium
end

RecordingStudioAgents.agents.register(
  key: :page_librarian,
  version: 1,
  name: "Page librarian",
  description: "Finds a page in the current workspace.",
  instructions: "Find the named page with the allowed tool.",
  profile: :low
)

RecordingStudioAgents.agent(:page_librarian, version: 1).run(
  task: task,
  root_recording: root,
  initiator: user,
  execution_source: :job,
  idempotency_key: job_id,
  profile: :high
)
```

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

`Results::Completed` carries in-memory output for the call that ran. Replay of a succeeded attempt returns `Results::Existing`. Adopting a completed Recording Studio AI run returns `Completed` when the reply is still readable, and `Existing` when it is not. Replay of a recorded handoff returns `Results::HandoffRequested` again so the host can route; `Agent#run` still does not start the target. `Results::Blocked` means a tool is waiting on confirmation. Calling `run` again with the same idempotency key stays `Blocked` and does not start another model call. If that model call has since finished and the reply is still readable, the same key returns `Completed`. A new idempotency key starts another attempt.

A failed run is retryable for timeouts and connection resets, and when Recording Studio AI marks the provider error retryable. Programmer errors such as `RuntimeError` are not retryable.

## Progress

`RecordingStudioAgents::Progress.for(run)` returns coarse steps for one attempt. Steps come from knowledge load plus Recording Studio AI tool invocations, joined by `recording_studio_ai_run_id` or `request_id` (`recording-studio-agents:<agent_run_id>`). Hosts can poll that helper from a job. Do not stream token text as progress, and do not copy model output onto the agent run.

Each step has a label and a badge: Done, Working, Waiting, or Failed. Tool labels use the tool name (for example "Find page"), not the registry key. The dummy home lists steps after a librarian run. Admin run rows show the labels in a Steps column, plus token and tool counts from the linked model call.

## Admin

The `agents` section is staff operations for this gem. The hub title is **Agents admin**. Widgets cover Failed runs, Attempts this period, Tokens this period, and Hungry agents, using Last 4 weeks (today through 27 days back). Links open Agents, Runs, Tasks, Usage by agent, and Evaluations.

Runs filters by agent, status, and date (Last 4 weeks by default), charts attempts over time, and links the AI run into Recording Studio AI. Agent keys in that filter come from workspaces the actor can view. The Runs table shows the agent name and a status badge. Names on Agents and Runs open that agent's details: key, instructions, skills, tools, knowledge, and who it can pass to. Skills and tools on that page open their own details. Usage by agent uses the same date window and shows attempts, outcomes, tokens, wait, and tools per agent version. Averages skip attempts whose model call is gone. Tasks show the goal and when it was created. Agents lists names, versions, and whether each is on, including agents that have not run. The actions menu turns an agent on or off. The registry key stays as an optional column.

Skills and skill packs stay in code. Skills are instructions other gems contribute. Skill packs are optional bundles loaded at run. They do not have hub catalog screens. Admin never displays chain-of-thought.

Hosts that use importmap must pin Recording Studio Admin controllers so screen tables load:

```ruby
pin_all_from RecordingStudioAdmin::Engine.root.join("app/javascript/recording_studio_admin/controllers"),
             under: "controllers/recording_studio_admin",
             to: "recording_studio_admin/controllers",
             preload: false
```

## Dummy app

`test/dummy` is a host that proves the gem. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. The home page runs the page librarian over Workspace, Folder, and Page, then lists what it did. That page uses a sidebar. Gem screens, including Admin and the workspace switcher, stay on Recording Studio's default layout. A support clerk is registered for optional-skill tests and does not appear as a second home action. `/admin` is the staff hub. Agents is `/admin/sections/agents`.

The dummy has a Playground page at `/playground`. The form sits on the left and the steps on the right. The right side is blank until a run has model turns. While a run is going, each turn shows up when that turn starts, and the list updates in place. Each turn is a collapse with a title and a progress badge. Open a turn to see that call as one hash, with input and output. A later call's input is the tool result, not the original instruction again. Pick a registered agent, write an instruction, and search for the tools and skills that run may use. Page librarian can list the workspace pages and the menu pages (Home, Playground, Staff, and Agents) before it looks one up by title. The dummy keeps model replies so that page can show the text. Admin model calls include workspace runs, so that call is listed.

The dummy generates with Gemini and decides with TypeSafe Jev (`RecordingStudioAI.decide`). Set `GEMINI_API_KEY` or `google_ai_studio` for generation, and `TYPESAFE_API_KEY` or `typesafe` for decisions. Without a generative key, the librarian demo uses an offline stub. Tests ignore those variables and do not call a live model provider.
