# Migration Notes

## Current Requirements

- Gem version `0.21.0`
- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio gemspec `~> 7.7`. This repository pins `~> 7.8` (tag `v7.8.0`). Hosts MUST run the Recording Studio 7.4, 7.5, and 7.7 migrations. The dummy does not vendor those migrations. Fresh installs use Recording Studio `db/install_migrate`.
- Recording Studio AI gemspec `~> 0.25`. This repository pins `~> 0.26` (tag `v0.26.0`)
- Metrics dummy tag `v0.10.0`
- Logs dummy tag `v0.9.0` (GitHub-only)
- Accessible dummy tag `v0.58.0`, Trashable dummy tag `v1.3.0` (`require: false`), and Root Switchable dummy tag `v0.17.0`
- Cache dummy tag `v0.8.0`
- FlatPack gemspec `>= 0.1.354`. The root and dummy Gemfiles pin `~> 0.2` (tag `v0.2.0`). Attachable `v0.34.0` requires FlatPack `>= 0.1.376`. Hosts moving to 0.2 remove the manual `flat_pack/heroicons` importmap pin and any `flat-pack--icon` controller registration.
- view_component `>= 4.14`, `< 5` (this repository locks `~> 4.19`)
- Users dummy tag `v0.37.0`, Oauth dummy tag `v0.25.1`, MCP dummy tag `v0.45.2` (`~> 0.45.2`), API dummy tag `v1.21.3`, Moveable dummy tag `v6.1.0`, Icons dummy tag `v0.5.0`, Admin dummy tag `v2.20.0`, Site Settings dummy tag `v0.6.0`, Attachable dummy tag `v0.34.0` (`require: false`)
- Public RubyGems and GitHub access for dependency installation

## Named MCP tools

0.21.0 renames the six chat tools. The old names are gone.

| Was | Now |
| --- | --- |
| `agent_chats_list` | `list_agent_chats` |
| `agent_chats_create` | `create_agent_chat` |
| `agent_chats_read` | `read_agent_chat` |
| `agent_chats_append` | `append_agent_chat` |
| `agent_items_list` | `list_agent_items` |
| `agent_items_read` | `read_agent_item` |

MCP tool text lives in `RecordingStudioAgents::McpCopy::Copy`. OpenAPI text for the same calls lives in `RecordingStudioAgents::Api::ToolCopy` and is written for HTTP clients. The two texts are separate.

Recording Studio MCP stays optional. This gem does not depend on it. When the host loads MCP 0.45 or newer, boot calls `RecordingStudioMcp.register_tool` with `endpoint:` for each name. Tools are opt-in, so a host that mounts MCP must add `RecordingStudioAgents::McpCopy.tool_names` to `register_server` `include_tools`. A server that leaves them out does not advertise the chat tools. `describe` is still present. Generic tree tools (`list`, `show`, `create`, `update`, `delete`, `capability_action`) are not in `tool_names`. Include those names yourself when the host still wants them, and call `register_type` for each recordable they should cover. MCP 0.45 advertises a generic tool only for a type registered that way.

MCP `0.45.2` needs Recording Studio API `>= 1.21.3`. The dummy pins MCP `~> 0.45.2` (`v0.45.2`) and API `v1.21.3`.

In-chat tools still use `RecordingStudioMcp::ToolSurface.for` and `RecordingStudioMcp::Dispatcher.call`. The six chat tools stay out of that list.

## Turning chats off

0.19.0 adds `config.enabled`. The default is `true`, so no host action is required and existing chats stay available. Set it to `false`, or to `enabled: false` in `config/recording_studio_agents.yml`, to hide the launcher and the chat frame, answer engine routes with 404, and refuse new messages and the agent chat tools. There is no table and no per-workspace setting. `ExpireSessionsJob` still closes expired chats. A boolean read from the environment at boot needs a process restart after it changes.

## Claiming a change

0.18.6 adds one line to the gem-owned preamble. The model may say a change is done only after a write tool returned success in this turn. Otherwise it calls the tool, or asks if something is unclear. A result from an earlier turn does not count. The line is sent with the hosted session on create. `threads.add_user_message` continues that session and does not send instructions again. A text-only reply still does not run a tool or change a recording. Chats opened before this release keep their stored preamble.

## Recording index

0.18.5 adds a recording index to the model input on `threads.create` and `threads.add_user_message`. It lists the current page, its parent, viewable siblings and children, and nearby recordings in that root. The cap is 25 entries and 4096 bytes of JSON. 0.18.7 reads `RecordingStudioAccessible.authorized_recordings` once per index for that root. A root grant is `Recording.within`. A narrower grant is the seeded descendant set, so a sibling outside the grant and a child nested under that sibling stay out. A turn grant that is not this root still uses that grant's own check. `config.recording_names` maps a class name to one column (`"Page" => "title"`). The gem default is `RecordingStudioAgents::Session` => `title`. Other types are type and id only. Access rows are left out. The `page_context` timing line adds `index_n=` and `index_ms=`. Write tools are unchanged.

## Chat list and timing

0.18.4 pages `threads.list` in SQL (`created_at` descending, then `id` descending) and checks Accessible on the fetched rows. The 50 cap, `has_more`, `after`, and page-parent filter are unchanged. Timing lines add `q=` and `db=`. A new chat logs `create_tools`, `create_provider`, and `create_persist`. A round logs `answers_ms=` and `model_ms=`. One turn reuses a single tool grant and tool surface. A write is still checked with Recording Studio and Accessible when the call runs. A dropped replay logs `dedupe dropped` with an item id and `by=id` or `by=text`, and no message text.

## Repeated assistant text

0.18.3 keeps one copy of an assistant message the provider sends again in the same turn. A repeat is a `message_completed` event with no text deltas. It is dropped when the provider item id and the text both match, or when there is no item id and the text matches a message already shown. Text deltas are kept. A different item id, different text, or the same words on the next turn are shown. Nothing is stored for a dropped repeat.

## ChatKit stream

0.18.2 writes `thread.created` (a new thread), the user message, and `stream_options` before the chat is saved and before the provider runs. The ids in those events are the ids that get stored. A declined send still stores nothing. A provider contract error during that save is an error event on the `200` stream. Invalid JSON, a rejected page, a missing thread, and a signed-out request stay JSON. Rails logs one `[recording_studio_agents.chatkit] timing` line per phase (`page_context`, `create` or `append`, `ttft`, `tool`, `round`, `total`) with durations only.

## MCP tool text

0.18.1 replaces the short MCP descriptions on the six agent chat tools. Names, arguments, access checks, and results are the same. No host change.

## Layout

Recording Studio 6 removed `RecordingStudio::UsesDefaultLayout`, `recording_studio_page_nav`, and the `:page_nav_back_*` / `:page_nav_anchor_*` slots. Set the page shell with `config.layout` on `RecordingStudioAgents::Configuration`. The engine controller calls `recording_studio_layout`. ChatKit sets `layout false` so JSON and server-sent events do not render that shell.

Leave `config.layout` as `nil` to use `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`. Assign `false` for no layout, a layout name, or `->(controller:) { ... }`. Anything else raises `ArgumentError` from `RecordingStudio::Layout.accept`.

On a screen, set `content_for :title` and, when you have one, `content_for :subtitle`. The default layout renders one `FlatPack::PageTitle`. Do not also render that title in the view body. The layout calls `strip` on those slots, which drops HTML safety, so pass the raw text with `html_safe`. `PageTitle` then escapes it once. Back and close go through `flat_pack_page_nav(round: true, style: :default, back_href:, back_tooltip:, anchor_href:, anchor_tooltip:)`. Page actions go through `register_page_nav`. Custom HTML on the right goes through `recording_studio_page_nav_right`.

`FlatPack::Card` takes `background:`, `border:`, and `shadow:`. It rejects `style:`.

The popup chat fills the iframe. `recording_studio_agents/popup.css` stops that document from scrolling. `config.launcher_icon` defaults to `:chat`, `config.launcher_label` to `"Open chat"`, and `config.popup_title` to `"Chat"`.

## Sibling gems

The dummy keeps the pins in the Requirements list. Cache `v0.7.0`, Attachable `v0.31.0`, Site Settings `v0.6.0`, and Icons `v0.4.0` still accept Recording Studio 7. The dummy Gemfile pins those tags. There is no Bundler gemspec rewrite.

Recording Studio 6.9 requires `recording_studio_events.root_recording_id`. Copy `AddRootRecordingIdToRecordingStudioEvents` from core and run `bin/rails db:migrate`. Closing a chat calls `recording.recordables(all: true)` so every session snapshot is deleted. Core 6.12 returns 50 events unless `all: true`.

Recording Studio refuses `record!` unless `config.authorize_write` is set. The dummy allows a write when an actor is present. `root_recording_for` only finds a root. Create one with `create_root_recording!(recordable, actor:)`. Trashable `v1.0.1` keeps the `v0.17.0` removal of `kept_sql`. Use `Recording.kept`. The events `root_recording_id` migration is already in the dummy. Root Switchable requires an Accessible `:view` grant on the current root before the mounted switch page renders. A blank current root still requires an actor.

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
