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

The generator copies `create_recording_studio_agents_sessions`, `scope_agents_idempotency_keys_to_root`, `require_agents_root_on_idempotency_keys`, and `add_instructions_to_recording_studio_agents_sessions`, in that order. The first creates the chat snapshot table, the binding table, and the item table.

A and B can run back to back. The generator copies both, and `db:migrate` runs A then B.

Migration A (`scope_agents_idempotency_keys_to_root`) adds a nullable `root_recording_id` and a foreign key that is not validated yet. It installs `rs_agents_fill_root_recording_id`, a `BEFORE INSERT` trigger on bindings and items that copies `recording_studio_recordings.root_recording_id` when the new row's root is null. It then backfills existing rows by walking `id` in batches of 1000. A recording whose own root is null cannot be filled. The migration raises with the remaining count, the recording ids, and a hint to set those roots and re-run, instead of scanning those rows again. A then creates unique indexes on `(root_recording_id, key)` concurrently and keeps the old global unique indexes, so old code still enforces one key across workspaces until B. A can be re-run after a partial failure: the column and foreign key use `if_not_exists`, the trigger is dropped and created again, and an invalid concurrent index is dropped before it is created again. Triggers use `DROP TRIGGER IF EXISTS` and `CREATE TRIGGER` inside one transaction, so a failed create restores the previous trigger. That does not require PostgreSQL 14.

Migration B (`require_agents_root_on_idempotency_keys`) backfills rows that arrived after A, validates the foreign keys, sets `NOT NULL` through a check constraint, and only then drops the old global unique indexes. It drops those indexes only when both new indexes are valid. The fill trigger stays in place after B. Old servers do not write `root_recording_id`, and the `NOT NULL` check would reject those inserts without the trigger. Drop the trigger in a later release, after every server writes the column itself. That later migration must use `DROP TRIGGER IF EXISTS` and `DROP FUNCTION IF EXISTS`, because a host that loaded `schema.rb` never created the trigger. B's `down` raises `ActiveRecord::IrreversibleMigration` because those global indexes cannot be restored once the same key exists in two workspaces.

`schema.rb` does not dump triggers. `db:schema:load` and the test suite therefore have no fill trigger. `agent_sessions_test` inserts a NULL-root item to prove the global-index clash, and that insert only stays NULL because the trigger is absent. Hosts that run A and B do get the trigger.

A and B set `lock_timeout` to 5 seconds only for the short locks (columns, the trigger, backfill, foreign keys, and `NOT NULL`). Concurrent index builds and drops run outside that limit, because a 5 second cap would cancel them on a busy database. The previous `lock_timeout` is saved and restored, including a value from `database.yml` and including when the backfill raises. If Postgres cancels a short statement for the 5 second timeout, re-run the migration.

`add_instructions_to_recording_studio_agents_sessions` adds a nullable `instructions` text column to `recording_studio_agents_sessions`. It sets `lock_timeout` to 5 seconds around that `ADD COLUMN` only, then restores the previous value, including a value from `database.yml`. The column has no default, so Postgres does not rewrite the table. Existing rows stay null. Old servers keep inserting without naming the column. `down` drops the column. No backfill.

`Binding` and `Item` copy `root_recording_id` from the recording before validation, so the new app writes the column before B requires it. Recording ids are unchanged. Recording Studio AI keeps its own run history; these migrations do not delete those rows.

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
