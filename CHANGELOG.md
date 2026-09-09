# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.6] - 2026-09-09

Agents admin hub links to the jobs staff actually open, and those buttons navigate.

### Changed
- Hub buttons are Runs, Tasks, Usage by agent, and Evaluations. Registered agents, skills, and skill packs stay as catalog screens and are not hub buttons.
- Tasks lists the goal and when it was created. It no longer shows the task key.
- The usage screen title is **Usage by agent**, with a subtitle that names attempts, outcomes, and average tokens. The screen key stays `agent_usage`.

### Fixed
- Hub title buttons navigate. Admin still passes `url:` into Flatpack Button, which only reads `href:`. This gem maps `url` to `href` until Admin ships that one-line template change.

### Upgrade notes
- No migration. Screen keys are unchanged.
- Bookmarks and widget links to `/admin/screens/agent_usage` still work. The visible title is Usage by agent, not By agent.
- Catalog screens remain at `registered_agents`, `registered_skills`, and `registered_skill_packs`. They are no longer linked from the hub.
- Do not copy the Flatpack Button `url` prepend in a host. It belongs in Admin when that gem passes `href:` on section hub buttons.

## [0.4.5] - 2026-09-08

Review follow-ups: stop storing unused task context, scope admin filters, tighten retries, and align hub widgets with Last 4 weeks.

### Changed
- Tasks keep `goal` for Admin. They no longer persist `context_json`. `TaskInput#context` still feeds the input digest.
- Admin Runs agent-key filter lists keys from workspaces the actor can view. With no actor it returns none.
- Failed runs are retryable for timeouts and connection resets, and when Recording Studio AI marks the provider error retryable. Programmer errors such as `RuntimeError` are not retryable.
- Adopting a completed Recording Studio AI run uses retained text when it is still readable. Without retained output the attempt finishes as `Results::Existing`, not `Completed` with empty text.
- Hub widgets use Last 4 weeks (today through 27 days back), matching Runs and By agent.

### Fixed
- Dummy workspace switcher uses Accessible instead of an always-true access check.
- Dummy demo generate stub is request-scoped. Tests stub `RecordingStudioAI.generate` instead of replacing the method on the singleton.

### Upgrade notes
- Install and run the engine migration that removes `recording_studio_agents_tasks.context_json`. Goal stays. `TaskInput` is unchanged.
- Hosts that retry `Results::Failed` should treat `failure.retryable?` as false for programmer errors. Timeouts and connection resets still retry.
- Hosts that treated an adopted completed AI run as `Results::Completed` with blank output now get `Results::Existing` unless retained text is still available.
- Hub widget copy and windows are Last 4 weeks. Date pickers still default to `last_4_weeks`.
- The Admin Period prepend that aligns Last 4 weeks with Flatpack stays in this gem until Admin ships the 27-day window. Do not copy that prepend in a host.
- Agents stay code-defined. This release does not add a JSON API, an enable-on-root mixin, or a separate evaluations pipeline. Evaluations still persist on an attempt and list in Admin.

## [0.4.4] - 2026-09-08

`Agent#run` rejects a `context_recording` from outside the task root.

### Fixed
- Passing a context recording from another tree raises `ContractError` before a task or run is written

### Upgrade notes
- `context_recording` is still optional. When you pass one, it must be the task root or a child inside that root.
- No migration.

## [0.4.3] - 2026-09-08

Knowledge entries must cite the recording they came from, so a loader cannot skip the task-root check.

### Changed
- `Knowledge::Entry` requires `source_recording`. Gatherer rejects a missing source or a source outside the task root.

### Upgrade notes
- Pass `source_recording:` on every knowledge entry. Use the recording the content came from (the task root or a child inside that root). Omitting it raises `ContractError`. A source outside the task root still raises `ConfigurationError`.
- No migration.

## [0.4.2] - 2026-09-08

Handoff recovery no longer drops a recorded request or crashes on replay.

### Fixed
- An expired lease with a recorded handoff target finishes as `handoff_requested`, not `succeeded`
- Replaying the same attempt key after a handoff returns `Results::HandoffRequested` instead of raising `InvalidTransition`
- The handoff tool requires the live lease from the generate call, so a stale worker cannot stamp a target onto a run another worker owns

### Upgrade notes
- Hosts that retry `Agent#run` after a handoff now get `Results::HandoffRequested` again. Keep the router idempotent; Agents still does not start the target.
- No migration.

## [0.4.1] - 2026-09-08

Admin date filters show Flatpack's Last 4 weeks preset instead of raw ISO dates.

### Fixed
- Runs and By agent date pickers use Flatpack's Last 4 weeks window (today through 27 days back) so the trigger reads **Last 4 weeks**

### Upgrade notes
- No host code change. Date filters still default to `last_4_weeks`. The window is one day shorter than Admin Period's four 7-day jumps, matching Flatpack.

## [0.4.0] - 2026-09-07

Coarse progress for an agent attempt, read from knowledge load and Recording Studio AI tool invocations.

### Added
- `RecordingStudioAgents::Progress.for(run)` returns ordered steps with Done / Working / Waiting / Failed badges
- Dummy page librarian lists those steps on home after a run
- Admin Runs table has a compact Steps column, plus Tokens and Tools from the linked Recording Studio AI call
- Admin hub widgets: Attempts this period, Tokens this period, Hungry agents, and Failed runs
- Admin By agent screen averages attempts, outcomes, tokens, wait, and tools per agent version

### Upgrade notes
- Call `Progress.for(run)` from a host screen or job poll. There is no new Agents migration.
- Join the AI run by `recording_studio_ai_run_id` or `request_id` `recording-studio-agents:<agent_run_id>`.
- Do not stream token text as progress, and do not copy model output or token totals onto the agent run.
- Open Recording Studio AI from Admin for the model call. Agents admin does not copy spend screens.

## [0.3.0] - 2026-09-07

Recording Studio Agents V1. This is a product release, not a template bump.

### Added
- Code registries for skills, knowledge, skill packs, and agents, compiled into an immutable program
- `optional_skills:` allowlist plus `pack:` / `extra_skills:` selection at `Agent#run`. Required `skills:` still always compile.
- `Agent#run` with a required `idempotency_key`, lease, and adoption of an existing Recording Studio AI run
- Task, agent run, activity, and evaluation tables. Runs store `output_digest`, selected skill refs, and an indexed `recording_studio_ai_run_id` with no foreign key. They do not copy model output.
- `awaiting_confirmation` run status and public `Results::Blocked`
- Internal handoff tool that records an allowlisted target and never starts it
- Recording Studio Admin section `agents` with read-only catalogs plus tasks, runs, and evaluations
- Dummy page librarian over Workspace, Folder, and Page. Dummy support clerk for optional-skill tests. Dummy importmap pins Turbo and Recording Studio Admin screen controllers so Admin tables load in the browser.

### Fixed
- Dummy Tailwind now resolves Bundler gem roots before build so Recording Studio layout and Admin table utilities are in the compiled CSS.

### Changed
- Gem identity is `recording_studio_agents` at `https://github.com/bowerbird-app/RecordingStudio_agents`
- Dependencies: `recording_studio ~> 4.2`, `recording_studio_ai ~> 0.3`, `recording_studio_admin ~> 2.0`, `recording_studio_accessible ~> 0.6`
- Dummy GitHub tags: Recording Studio `v4.2.0`, AI `v0.3.1`, Admin `v2.0.2`, Accessible `v0.7.0`, FlatPack `v0.1.143`

### Removed
- Template Example capability and dummy `/docs/*` starter pages

### Upgrade notes
- Point hosts at this gem instead of the addon template. Rename leftover template constants and mount paths.
- Install Agents migrations. There is no pages sample table.
- Configure `RecordingStudioAI.configuration.authorization_handler`. Agents does not add a second handler.
- Register skills, knowledge, skill packs, and agents in an initializer. Call `Agent#run` with `idempotency_key: job_id` from Active Job so retries converge.
- `skills:` stay always-on. Put ticket-specific procedures on `optional_skills:` and load them with `pack:` or `extra_skills:` at run time. Same attempt key plus a different selected set raises `IdempotencyConflict`.
- Install the selected-skills migration so agent runs can store which extra skills were loaded.
- Mount Recording Studio Admin and enable the `agents` section on an admin root.
- Pin Recording Studio Admin Stimulus controllers in the host importmap so Admin screen tables load. The dummy importmap shows the pin.

## [0.2.1] - 2026-09-01

Template Cloud Agent environment. See git history for the template notes that shipped under this version.

[0.4.6]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.4.6
[0.4.5]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.4.5
[0.4.4]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.4.4
[0.4.3]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.4.3
[0.4.2]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.4.2
[0.4.1]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.4.1
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.4.0
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.3.0
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.2.1
