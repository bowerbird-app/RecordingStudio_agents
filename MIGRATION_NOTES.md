# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `~> 4.7` (dummy GitHub tag `v4.7.0`)
- Recording Studio AI `~> 0.15.1` (dummy GitHub tag `v0.15.1`)
- Metrics dummy tag `v0.3.1`
- Accessible dummy tag `v0.20.0`, Trashable dummy tag `v0.11.1` (`require: false`), and Root Switchable dummy tag `v0.9.5`
- Cache dummy tag `v0.5.1`
- FlatPack dummy tag `v0.1.254` (Oauth requires `~> 0.1.198`)
- Users dummy tag `v0.24.0`, Oauth dummy tag `v0.12.5`, MCP dummy tag `v0.19.1`, API dummy tag `v0.11.4`, Admin dummy tag `v2.3.3`, Site Settings dummy tag `v0.5.1`
- Metrics stays `v0.3.1` because MCP, Root Switchable, and Trashable `v0.11.1` require metrics `< 0.4`
- Public RubyGems and GitHub access for dependency installation

## Host migration

```bash
bin/rails generate recording_studio_agents:migrations
bin/rails db:migrate
```

The generator copies `create_recording_studio_agents_sessions`, `scope_agents_idempotency_keys_to_root`, and `require_agents_root_on_idempotency_keys`, in that order. The first creates the chat snapshot table, the binding table, and the item table.

Deploy the idempotency change in two steps. Migration A (`scope_agents_idempotency_keys_to_root`) adds a nullable `root_recording_id`, backfills it from each row's recording in batches, creates unique indexes on `(root_recording_id, key)` concurrently, then drops the old global unique indexes. Migration B (`require_agents_root_on_idempotency_keys`) backfills rows that showed up after A and then sets `NOT NULL`. Ship A with the app release that copies `root_recording_id` from the recording, then ship B. Do not run B first.

A cannot be reversed. `down` raises `ActiveRecord::IrreversibleMigration` because putting the global unique indexes back fails once the same key exists in two workspaces. B can relax the null constraint. Recording ids are unchanged. Recording Studio AI keeps its own run history; these migrations do not delete those rows.

Hosts that mount MCP also copy migrations from Recording Studio API, Oauth, MCP, and Users. Those gems own those tables.

## Verification

Install both bundles and run the complete gem and dummy app test path:

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
```

Run the dummy app from its directory for browser verification:

```bash
cd test/dummy
bin/dev
```

Use the [FlatPack repository](https://github.com/bowerbird-app/flatpack) and the live FlatPack demo linked from the top-level README for current component documentation.
