# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `>= 6.1.0` (dummy GitHub tag `v6.1.0`)
- Recording Studio AI `~> 0.19.0` (dummy GitHub tag `v0.19.1`)
- Metrics dummy tag `v0.7.0`
- Logs dummy tag `v0.7.1` (GitHub-only; AI 0.19.1 depends on it)
- Accessible dummy tag `v0.20.0`, Trashable dummy tag `v0.11.3` (`require: false`), and Root Switchable dummy tag `v0.9.7`
- Cache dummy tag `v0.5.1`
- FlatPack `>= 0.1.315` at commit `1fcbafe94f8eb118f0a22182f63f5110fcc97a56` (version 0.1.319). Oauth requires `~> 0.1.198`, which this commit satisfies.
- view_component `>= 4.14`, `< 5` (this repository locks `4.19.0`)
- Users dummy tag `v0.25.2`, Oauth dummy tag `v0.15.1`, MCP dummy tag `v0.22.0`, API dummy tag `v0.16.0`, Admin dummy tag `v2.3.3`, Site Settings dummy tag `v0.5.1`, Attachable dummy tag `v0.20.2` (`require: false`)
- Public RubyGems and GitHub access for dependency installation

## Layout

Recording Studio 6 removed `RecordingStudio::UsesDefaultLayout`, `recording_studio_page_nav`, and the `:page_nav_back_*` / `:page_nav_anchor_*` slots. Set the page shell with `config.layout` on `RecordingStudioAgents::Configuration`. The engine controller calls `recording_studio_layout`. ChatKit sets `layout false` so JSON and server-sent events do not render that shell.

Leave `config.layout` as `nil` to use `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`. Assign `false` for no layout, a layout name, or `->(controller:) { ... }`. Anything else raises `ArgumentError` from `RecordingStudio::Layout.accept`.

On a screen, set `content_for :title` and, when you have one, `content_for :subtitle`. The default layout renders one `FlatPack::PageTitle`. Do not also render that title in the view body. The layout calls `strip` on those slots, which drops HTML safety, so pass the raw text with `html_safe`. `PageTitle` then escapes it once. Back and close go through `flat_pack_page_nav(round: true, style: :default, back_href:, back_tooltip:, anchor_href:, anchor_tooltip:)`. Page actions go through `register_page_nav`. Custom HTML on the right goes through `recording_studio_page_nav_right`.

`FlatPack::Card` takes `background:`, `border:`, and `shadow:`. It rejects `style:`.

## Sibling gems

The dummy keeps the pins in the Requirements list. AI `v0.19.1`, Metrics `v0.7.0`, and Logs `v0.7.1` allow Recording Studio `>= 6.1.0`. Trashable `v0.11.3`, Users `v0.25.2`, Root Switchable `v0.9.7`, Attachable `v0.20.2`, and the other dummy pins listed above still declare `recording_studio` below 5. Both Gemfiles require `test/support/widen_recording_studio_requirement.rb` so Bundler can resolve 6.1.0 beside those pins. That file is not installed with the gem.

Site Settings `v0.5.1` still includes `RecordingStudio::UsesDefaultLayout`. The dummy defines an empty module in `test/dummy/config/application.rb` until that gem stops. Root Switchable `v0.9.7` still passes PageNav `anchor_url` / `anchor_label` and Card `style:`. `test/dummy/config/initializers/flatpack_removed_kwargs.rb` accepts those keywords. A host on the same pins needs the same two shims.

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
