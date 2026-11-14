# Migration Notes

## Current Requirements

- Gem version `0.12.0`
- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `~> 6.0, >= 6.12.0` (dummy GitHub tag `v6.12.0`)
- Recording Studio AI `>= 0.21.2, < 1.0` (dummy GitHub tag `v0.21.2`)
- Metrics dummy tag `v0.8.0`
- Logs dummy tag `v0.7.4` (GitHub-only; AI 0.21.2 depends on it)
- Accessible dummy tag `v0.32.0`, Trashable dummy tag `v0.14.0` (`require: false`), and Root Switchable dummy tag `v0.15.0`
- Cache dummy tag `v0.6.3`
- FlatPack `>= 0.1.354`. The root Gemfile and the dummy pin tag `v0.1.356`. `FloatingFrame` shipped in `v0.1.354`.
- view_component `>= 4.14`, `< 5` (this repository locks `4.19.0`)
- Users dummy tag `v0.28.1`, Oauth dummy tag `v0.21.7`, MCP dummy tag `v0.33.2`, API dummy tag `v0.23.0`, Moveable dummy tag `v4.1.1`, Icons dummy tag `v0.2.1`, Admin dummy tag `v2.13.0`, Site Settings dummy tag `v0.5.6`, Attachable dummy tag `v0.23.0` (`require: false`)
- Public RubyGems and GitHub access for dependency installation

## Layout

Recording Studio 6 removed `RecordingStudio::UsesDefaultLayout`, `recording_studio_page_nav`, and the `:page_nav_back_*` / `:page_nav_anchor_*` slots. Set the page shell with `config.layout` on `RecordingStudioAgents::Configuration`. The engine controller calls `recording_studio_layout`. ChatKit sets `layout false` so JSON and server-sent events do not render that shell.

Leave `config.layout` as `nil` to use `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`. Assign `false` for no layout, a layout name, or `->(controller:) { ... }`. Anything else raises `ArgumentError` from `RecordingStudio::Layout.accept`.

On a screen, set `content_for :title` and, when you have one, `content_for :subtitle`. The default layout renders one `FlatPack::PageTitle`. Do not also render that title in the view body. The layout calls `strip` on those slots, which drops HTML safety, so pass the raw text with `html_safe`. `PageTitle` then escapes it once. Back and close go through `flat_pack_page_nav(round: true, style: :default, back_href:, back_tooltip:, anchor_href:, anchor_tooltip:)`. Page actions go through `register_page_nav`. Custom HTML on the right goes through `recording_studio_page_nav_right`.

`FlatPack::Card` takes `background:`, `border:`, and `shadow:`. It rejects `style:`.

## Sibling gems

The dummy keeps the pins in the Requirements list. Accessible `v0.32.0`, Trashable `v0.14.0`, Cache `v0.6.3`, Attachable `v0.23.0`, Site Settings `v0.5.6`, and Icons `v0.2.1` accept Recording Studio `>= 6.1.0`. The Gemfiles pin those tags. There is no Bundler gemspec rewrite.

Recording Studio 6.9 requires `recording_studio_events.root_recording_id`. Copy `AddRootRecordingIdToRecordingStudioEvents` from core and run `bin/rails db:migrate`. Closing a chat calls `recording.recordables(all: true)` so every session snapshot is deleted. Core 6.12 returns 50 events unless `all: true`.

Recording Studio 6.5 refuses `record!` unless `config.authorize_write` is set. The dummy allows a write when an actor is present. Trashable `v0.14.0` adds nullable `purge_at` on `recording_studio_recordings`. Copy that migration and run `bin/rails db:migrate`, then `bin/rails recording_studio_trashable:restamp_purge_at` on a database that already has trash. Root Switchable `v0.15.0` requires an Accessible `:view` grant on the current root before the mounted switch page renders. A blank current root still requires an actor.

## Host migration

```bash
bin/rails generate recording_studio_agents:migrations
bin/rails db:migrate
```

The generator copies `create_recording_studio_agents_sessions`, `scope_agents_idempotency_keys_to_root`, `require_agents_root_on_idempotency_keys`, `add_instructions_to_recording_studio_agents_sessions`, and `create_recording_studio_agents_chat_tool_audits`, in that order. The first creates the chat snapshot table, the binding table, and the item table. The last creates `recording_studio_agents_chat_tool_audits`. That table is registered with Recording Studio Logs as an unpartitioned UUID log, `retention: :indefinite`, with no summary. Do not schedule a Logs partition job for it. A row stores the actor, the chat recording id, the provider turn id, the round number, the tool name, read or write, at most 50 identifier-like argument keys, the outcome, and the call id. It does not store argument values. A unique index on `(provider_turn_id, call_id)` keeps one row per call in a turn. There is no separate index on `provider_turn_id` alone. Null turn ids stay distinct, so a direct call with no turn can repeat a call id. The row is inserted as `pending` before the tool runs, under the same PostgreSQL advisory lock as the write count and the round number. A repeated call id joins the row already started, does not run the tool, and does not change that row. A live duplicate is left out of the posted results, and that round ends with no ChatKit event. A dispatch that passes `chat_tool_deadline` posts a timeout and stores `unknown` when the pending update wins. A pending row is also stale once `occurred_at` is older than that deadline plus a 30 second grace. `chat_tool_stale_after` must be longer than that. A stale join is posted as unknown only when a conditional update moves it out of pending. Do not run a chat tool round inside an open transaction unless `allow_chat_tools_in_transaction` is true. `config.mcp_tool_allow = []` blocks every tool.

A and B can run back to back. The generator copies both, and `db:migrate` runs A then B.

Migration A (`scope_agents_idempotency_keys_to_root`) adds a nullable `root_recording_id` and a foreign key that is not validated yet. It installs `rs_agents_fill_root_recording_id`, a `BEFORE INSERT` trigger on bindings and items that copies `recording_studio_recordings.root_recording_id` when the new row's root is null. It then backfills existing rows by walking `id` in batches of 1000. A recording whose own root is null cannot be filled. The migration raises with the remaining count, the recording ids, and a hint to set those roots and re-run, instead of scanning those rows again. A then creates unique indexes on `(root_recording_id, key)` concurrently and keeps the old global unique indexes, so old code still enforces one key across workspaces until B. A can be re-run after a partial failure: the column and foreign key use `if_not_exists`, the trigger is dropped and created again, and an invalid concurrent index is dropped before it is created again. Triggers use `DROP TRIGGER IF EXISTS` and `CREATE TRIGGER` inside one transaction, so a failed create restores the previous trigger. That does not require PostgreSQL 14.

Migration B (`require_agents_root_on_idempotency_keys`) backfills rows that arrived after A, validates the foreign keys, sets `NOT NULL` through a check constraint, and only then drops the old global unique indexes. It drops those indexes only when both new indexes are valid. The fill trigger stays in place after B. Old servers do not write `root_recording_id`, and the `NOT NULL` check would reject those inserts without the trigger. Drop the trigger in a later release, after every server writes the column itself. That later migration must use `DROP TRIGGER IF EXISTS` and `DROP FUNCTION IF EXISTS`, because a host that loaded `schema.rb` never created the trigger. B's `down` raises `ActiveRecord::IrreversibleMigration` because those global indexes cannot be restored once the same key exists in two workspaces.

`schema.rb` does not dump triggers. `db:schema:load` and the test suite therefore have no fill trigger. `agent_sessions_test` inserts a NULL-root item to prove the global-index clash, and that insert only stays NULL because the trigger is absent. Hosts that run A and B do get the trigger.

A and B set `lock_timeout` to 5 seconds only for the short locks (columns, the trigger, backfill, foreign keys, and `NOT NULL`). Concurrent index builds and drops run outside that limit, because a 5 second cap would cancel them on a busy database. The previous `lock_timeout` is saved and restored, including a value from `database.yml` and including when the backfill raises. If Postgres cancels a short statement for the 5 second timeout, re-run the migration.

`add_instructions_to_recording_studio_agents_sessions` adds a nullable `instructions` text column to `recording_studio_agents_sessions`. Run it before booting servers that read or write that column. It sets `lock_timeout` to 5 seconds around that `ADD COLUMN` only, then restores the previous value, including a value from `database.yml`. The column has no default, so Postgres does not rewrite the table. Existing rows stay null. `down` drops the column. No backfill.

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
