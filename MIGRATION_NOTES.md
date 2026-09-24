# Migration Notes

## 0.5.0

Run the engine migration that adds `recording_studio_agents_agent_runs.working_state_json` and `recording_studio_agents_agent_steps`.

```bash
bin/rails generate recording_studio_agents:migrations
bin/rails db:migrate
```

Development and dummy Gemfiles pin Recording Studio AI `v0.6.0`. Tool steps call `RecordingStudioAI.perform_tool`. Install that gem's migration and run it.

```bash
bin/rails recording_studio_ai:install:migrations
bin/rails db:migrate
```

The migration allows operation `tool` and adds `arguments` and `result` on custom tool invocations. No Agents configuration change. A missing `perform_tool` still fails the run with `tool_unavailable`, and the tool step is marked failed. Answer-only `generate` results still complete.

Existing `Agent#run` calls, skills, packs, knowledge loaders, and handoff allowlists stay valid. A generate result without `action_candidates` still finishes from that text. Agent budgets are separate from `maximum_attempts` and `maximum_custom_tool_rounds`.

Plans now include each allowed tool's parameters from the Recording Studio AI registry. No host change. Put required fields on the tool registration. The internal handoff tool is not listed there. A handoff candidate still names an allowlisted target.

A tool candidate whose arguments fail that tool's schema gets one more generate call for those arguments. The call counts toward `maximum_reasoner_calls`. The tool runs after the arguments validate. No host change.

An explicit empty `action_candidates` list now enters the runtime. A generate result that omits that key still finishes from its text. A failed final answer fails the run with `synthesis_failed`. The compiled instruction names a handoff candidate. A resume keeps a stored tool outcome when Recording Studio AI has one.

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `~> 4.2` (dummy GitHub tag `v4.2.0`)
- Recording Studio AI `~> 0.3` (dummy and development tag `v0.6.0`)
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
