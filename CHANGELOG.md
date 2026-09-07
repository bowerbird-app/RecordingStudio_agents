# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.3.0
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_agents/releases/tag/v0.2.1
