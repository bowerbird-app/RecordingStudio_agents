# Recording Studio Agents

Recording Studio Agents defines reusable agents in code and records each task attempt as an `AgentRun`. An agent compiles exact versions of its skills, tools, knowledge sources, and allowed handoff targets into one immutable program. `Agent#run` validates the task, authorizes the actor through Recording Studio AI, creates or reuses the run, and executes that run.

A plan that returns action candidates continues as a durable loop. The loop stores working state on the `AgentRun`, asks `RecordingStudioAI.decide` which candidate to take, and runs one tool through `RecordingStudioAI.perform_tool`. The next model call sees the current state, not a concatenation of earlier tool exchanges. A generate call that returns text and no action candidates still finishes from that one call.

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

An **agent run** is one attempt. It stores status, working state, an optional output digest, the handoff allowlist from the program that started it, and the latest Recording Studio AI run id. It does not copy prompts, raw tool payloads, or chain-of-thought. Duplicate delivery of the same `idempotency_key` reuses that attempt. A different task or a different context recording for that key raises `IdempotencyConflict`.

An **agent step** is one transition inside that attempt. The step stores its sequence, status, action type, candidate id, tool key when the action is a tool, an argument digest, a short observation, and the controller outcome. A plan step also stores the objective, plan lines, and success criteria written at that moment. A later plan does not rewrite that record. A request for the next actions stores those action lines. A handoff stores the reviewer. Statuses are `planned`, `started`, `completed`, `failed`, `awaiting_confirmation`, and `unresolved`. The step does not store tool arguments or tool result bodies.

**Working state** is the bounded document the next action is rebuilt from. It holds the goal, the plan, the current objective, success criteria, findings, completed work, failed approaches, open questions, a short window of recent observations, and counters. The step table keeps the older history. That history is not copied into the next prompt.

A **controller** call is one `RecordingStudioAI.decide` request. It asks whether the latest step made progress, whether the success criteria look met, whether the run looks stuck, whether it needs a new plan, and which listed candidate should go next. Each choice includes that candidate's purpose. A tool choice also names the tool and version. When no candidates remain and an observation is already stored, it asks whether the goal can be answered from those observations. The decision model returns probabilities. It does not write tool arguments, queries, or prose.

A **reasoner** call is one `RecordingStudioAI.generate` request on the run profile (`low`, `medium`, or `high`). The first call writes the plan, the success criteria, and the action candidates. Later calls replan, fill tool arguments that failed the tool's own check, or write the final answer. The controller uses `controller_profile`, which starts at `:low`. Agents does not name a provider or a model.

A long or nested tool result gets one more `generate` call on `controller_profile`. The call returns a short summary and a state delta. It counts toward `maximum_observation_calls`, not `maximum_reasoner_calls`. A string, a summary field, a page list, and a record of short fields skip that call. A title by itself is stored as `Found {title}`. Any other short field stays in the sentence, including a false found flag, a path, a folder, and an id. A page list keeps a path or a folder beside the title. Fields named secret, token, password, or credential stay out of the summary and out of that prompt.

A plan keeps at most three tool actions, plus a deliver or handoff candidate when the plan includes one. When those tools are finished and the observations do not answer the goal, one `generate` call on the run profile asks for the next one to three actions. That call counts toward `maximum_reasoner_calls`. It does not replace the plan or the success criteria, and it does not count as a replan. Arguments that already match the tool schema are kept. Arguments that do not match get the same argument fill as a plan. A stuck run still replans and replaces the plan.

An **action candidate** is one next action with its arguments already filled in. Kinds are `tool`, `deliver`, and `handoff`. A tool candidate names the tool key, the version, and an arguments object. The type is `tool`. The plan lists each allowed tool with the description, use, parameters, and return value from its Recording Studio AI registration, and the reasoner fills those arguments. When a tool candidate fails that tool's argument check, one more generate call uses that tool's parameter schema and returns the arguments object. That prompt includes the recent observations and the findings. That call counts toward `maximum_reasoner_calls`. The tool runs after those arguments validate. A candidate that still fails is dropped before the tool runs. An empty arguments object stays put when the tool requires nothing. Deliver and handoff candidates are left as they are. The internal handoff tool stays off that list. A handoff candidate still names an allowlisted target. The controller picks an id from the candidates that remain. A tool the program did not allow is dropped. A plan with nothing left goes back to the reasoner when no observation is stored yet. After an observation, an empty menu asks whether the goal can be answered from those observations. The runtime does not add a candidate of its own. The answer is written when that finished score crosses the threshold, or when every success criterion is already met.

A **tool** stays registered with Recording Studio AI. The runtime calls `RecordingStudioAI.perform_tool` for one candidate. That call keeps validation, authorization, confirmation, timeout, and result-size limits. Agents does not call a tool executor itself. Recording Studio AI 0.6.0 provides `perform_tool`. Hosts run that gem's migration so a run can use operation `tool`. A missing `perform_tool` still fails the tool step with `tool_unavailable`. Answer-only runs still finish from `generate`.

A **checkpoint** writes the working state and the current step, then renews the lease when the same worker still holds it. A new worker resumes from the last checkpoint. It does not repeat a finished tool. If Recording Studio AI already stored that tool's outcome, the resume keeps the stored outcome. A tool that never finished is closed as `unresolved` and is not run again. A failed final answer fails the run. An explicit empty `action_candidates` list enters the runtime. A generate result with no `action_candidates` key still finishes from its text.

Event history is the activity log plus the step rows. It is there to inspect. Memory that lasts across separate runs is not part of this version. Knowledge is loaded once for the attempt and kept in the system instruction. It is not written into working state as a second copy of the source text.

```text
AgentRun working state
        |
        v
Reasoner (RecordingStudioAI.generate)
plan, success criteria, action candidates
        |
        v
Controller (RecordingStudioAI.decide)
progress, finished, stuck, next candidate
        |
        +--> one tool (RecordingStudioAI.perform_tool)
        |         |
        |         v
        |    short observation, state delta, checkpoint
        |    next one to three actions when no tool is left
        |
        +--> controller again when an observation is stored and no candidates remain
        |
        +--> reasoner again when stuck, uncertain, or the observations do not answer the goal
        |
        +--> final answer
```

## Budgets, stuck runs, and confirmation

Agent budgets are separate from Recording Studio AI attempt limits. Raising `maximum_attempts` or `maximum_custom_tool_rounds` does not lengthen an agent. The host defaults are:

- `maximum_steps` 80
- `maximum_tool_actions` 30
- `maximum_reasoner_calls` 8
- `maximum_replans` 3
- `maximum_observation_calls` 30
- `maximum_runtime_seconds` 1800
- `soft_working_state_bytes` 6000
- `maximum_working_state_bytes` 12000

The controller treats a run as finished when `finished` is at least `finished_probability` (0.8) and `stuck` is below `stuck_probability` (0.7). The same thresholds apply when no candidates remain and an observation is stored. A lower finished score sends that run back to the reasoner. A choice whose top two probabilities differ by less than `choice_margin` (0.15) is uncertain, and the run asks the reasoner. A failed decision is not treated as finished. If another reasoner call is still inside the budget, the run replans. Otherwise the run fails with `decision_failed`. Success criteria that are already met write the answer even when the menu is empty.

Ruby detects an identical tool fingerprint three times, or three steps whose findings, completed work, and criteria did not change. The fingerprint hashes the tool key, the tool version, and the arguments. That streak asks for a new plan. The decision model can also report that the work looks stuck. Replanning stops at `maximum_replans` with failure code `maximum_replans`.

Once an observation is stored and working state is over `soft_working_state_bytes`, one `generate` call on the low profile rewrites findings, completed work, failed approaches, and recent observations. That call does not count toward `maximum_reasoner_calls`. It runs at most three times. The goal, the success criteria, and the step history stay. Past `maximum_working_state_bytes`, Ruby drops the oldest observations and then the oldest findings.

A tool that needs confirmation checkpoints the step as `awaiting_confirmation` and stops. The same idempotency key resumes that step. It does not start the plan over, and it does not repeat tools that already finished.

A **handoff** stays an allowlisted terminal outcome of the current run. The controller can select a handoff candidate only when that target is on the allowlist stored on the run. `Agent#run` does not start the target. The host routes the next call. If a worker dies after recording the target, a retry with the same idempotency key finishes as `handoff_requested` instead of succeeding. The internal handoff tool remains registered so older runs can still record a handoff during a generate call. The durable loop does not call that tool.

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

Tools named only by an unselected optional skill are dropped from that run. They still belong on the agent allowlist and in Recording Studio AI.

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

`skills:` replaces that selection for one run, including the agent's required skills. Pass a hash of registered skills, or `{}` for no skill blocks. It cannot be combined with `pack:` or `extra_skills:`. `tools:` narrows the tools that run may call to a subset of the agent's tools. Omit it to keep the usual allowlist. A skill on that run still needs its required tools in the subset, and a tool the agent does not list is rejected.

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

`RecordingStudioAgents::Progress.for(run)` returns coarse steps for one attempt. When the run has agent steps, the labels come from those steps, in sequence. Plan, Checked in, the tool name, and Answer are the usual ones, plus knowledge and a closing status. A run with no agent steps still uses knowledge plus the tool invocations on the linked Recording Studio AI run, joined by `recording_studio_ai_run_id` or `request_id` (`recording-studio-agents:<agent_run_id>`). Hosts can poll that helper from a job. Do not stream token text as progress, and do not copy the full model transcript onto the agent run.

Each step has a label and a badge: Done, Working, Waiting, or Failed. Tool labels use the tool name (for example "Find page"), not the registry key. The dummy home lists steps after a librarian run. Admin run rows show the labels in a Steps column. Token totals add the model calls linked from those steps, and fall back to the single AI run id on older rows. Optional columns show the current objective, plan count, check-in count, replan count, and whether the run looks stuck.

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

The dummy has a Playground page at `/playground`. The form sits on the left and the steps on the right. The right side is blank until a run has steps. While a run is going, the list updates in place. Each step is a collapse with a title and a progress badge. A durable run shows Plan, Decision, each tool, and Answer. Open a step to see what that step recorded. A plan step shows the plan written then. A decision shows that choice, and names the tool when one was picked. A tool step shows that tool's note. A step that called a model shows that call's profile and model. Earlier steps keep their own record when a later plan replaces the current objective. A failed run adds a last step with the reason it stopped. The exchange does not include tool arguments. Page librarian can list the workspace pages and the menu pages (Home, Playground, Staff, and Agents) before it looks one up by title. Without a generative key, that playground run uses an offline stub of the durable loop. The home button still uses a one-reply stub so the demo finishes without `perform_tool`. Admin model calls include workspace runs, so that call is listed.

The dummy generates with Gemini and decides with TypeSafe Jev (`RecordingStudioAI.decide`). Set `GEMINI_API_KEY` or `google_ai_studio` for generation, and `TYPESAFE_API_KEY` or `typesafe` for decisions. Without a generative key, the librarian demo uses an offline stub. Tests ignore those variables and do not call a live model provider.
