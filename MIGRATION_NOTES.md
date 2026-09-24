# Migration Notes

## 0.5.0

Run the engine migration that adds `recording_studio_agents_agent_runs.working_state_json` and `recording_studio_agents_agent_steps`.

```bash
bin/rails generate recording_studio_agents:migrations
bin/rails db:migrate
```

Development and dummy Gemfiles pin Recording Studio AI `v0.5.0`. That release does not add `perform_tool`. A tool step raises `ConfigurationError` until a later AI release provides that method and its migration for operation `tool`. Answer-only `generate` results still complete.

Existing `Agent#run` calls, skills, packs, knowledge loaders, and handoff allowlists stay valid. A generate result without `action_candidates` still finishes from that text. Agent budgets are separate from `maximum_attempts` and `maximum_custom_tool_rounds`.

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `~> 4.2` (dummy GitHub tag `v4.2.0`)
- Recording Studio AI `~> 0.3` (dummy and development tag `v0.5.0`)
- Recording Studio Admin `~> 2.0` (dummy tag `v2.0.2`)
- Accessible `~> 0.6` (dummy tag `v0.7.0`)
- Root Switchable dummy tag `v0.5.0`
- FlatPack dummy tag `v0.1.143`

## Verification

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
```

Run the dummy app from its directory:

```bash
cd test/dummy
bin/dev
```
