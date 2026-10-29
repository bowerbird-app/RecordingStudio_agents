# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.0] - 2026-10-29

### Changed
- Require Recording Studio AI `~> 0.19.0`. The dummy pins AI `v0.19.1` and Metrics `v0.7.0`. AI `v0.15.1` through `v0.18.1` still require Recording Studio `~> 4.7`, so they cannot install beside this gem's Recording Studio `>= 6.1.0`.
- The root Gemfile sources Recording Studio Logs from GitHub at `v0.7.1`. AI 0.19.1 depends on Logs `>= 0.4.1`, `< 1.0`, and Logs is not published on RubyGems. Logs `v0.7.0` requires Metrics `~> 0.6.1`, which rejects Metrics 0.7.0. Logs `v0.7.1` allows Metrics `>= 0.6.1`, `< 1.0` and Recording Studio `>= 6.1.0`. This gem does not call Logs. AI 0.19.1 still registers with the same `RecordingStudioLogs.register` keywords Logs 0.5.0 accepted.
- Dummy pins that rejected Metrics 0.7.0 move to Trashable `v0.11.3`, Root Switchable `v0.9.7`, and Attachable `v0.20.2`. Users moves to `v0.25.2`. The dummy Logs pin moves to `v0.7.1`.

### Host upgrade notes
Hosts moving to `recording_studio_ai ~> 0.19`, Metrics 0.7, and Logs 0.7.1:

- This agents gem adds no migration of its own. AI and Logs do.
- Recording Studio AI `v0.19.1` requires `recording_studio >= 6.1.0`, `recording_studio_logs >= 0.4.1, < 1.0`, and `recording_studio_metrics >= 0.3.0, < 1.0`. AI 0.19.0 removed `RecordingStudio::UsesDefaultLayout`. Metrics `v0.7.0` requires `recording_studio >= 6.1.0`. Logs `v0.7.1` requires `recording_studio >= 6.1.0` and `recording_studio_metrics >= 0.6.1, < 1.0`. Logs `v0.7.0` requires Metrics `~> 0.6.1`, which rejects Metrics 0.7.0. Add a GitHub source for Logs. It is not published on RubyGems.
- AI 0.18.0 added `db/migrate/20261021120000_add_root_recording_id_to_recording_studio_ai_call_logs.rb` (`AddRootRecordingIdToRecordingStudioAICallLogs`). That file is on the `v0.19.1` tag and was not on `v0.17.1`. AI's 0.18.0 upgrade notes install it with `bin/rails recording_studio_ai:install:migrations`, then `bin/rails db:migrate`. The `recording_studio_ai:install` generator copies the initializer and the engine mount. It does not copy migrations.
- AI 0.18.0 depends on Recording Studio Logs. Logs 0.6.0 and later must be migrated before boot. Logs `v0.7.1` documents `bin/rails generate recording_studio_logs:migrations`, then `bin/rails db:migrate`. That generator copies `20261015000001_create_recording_studio_logs_runs.rb` and `20261021000001_rename_aggregation_run_day_to_period_start.rb`. The rename is the 0.6.0 change from aggregation run `day` to `period_start`.
- Metrics 0.7.0 was blocked by Trashable `v0.11.1` (`recording_studio_metrics >= 0.3.0, < 0.4`), Root Switchable `v0.9.5` (`>= 0.3.0, < 0.4`), and Attachable `v0.20.1` (`>= 0.3.0, < 0.6`). Users `v0.24.0` requires Metrics `~> 0.3`, which is `>= 0.3` and `< 1.0`, so that pin accepts Metrics 0.7.0.

## [0.8.0] - 2026-10-28

### Removed
- Tracked SimpleCov output under `coverage/` and `test/dummy/coverage/`. Those directories are gitignored.
- `docs/gem_template/` template architecture notes. Product docs stay in the README and `docs/layout.md`.
- Dummy nested `test/dummy/.github/workflows/ci.yml`. CI is the repository workflow only.
- Template `:example` capability (`RecordingStudio::Capabilities::Example`) and the dummy Workspace opt-in for it.
- `RecordingStudioAgents::ExtensionInstaller` and the engine initializers that `class_eval`'d host models and controllers.
- Empty engine root (`HomeController#index`). The mount still serves `POST /chatkit`.

### Changed
- Dummy `config.app_name` is "Recording Studio Agents Dummy".

### Upgrade notes
- No database migration.
- Drop `include RecordingStudio::Capabilities::Example.to(...)` from host models. This gem no longer registers `:example`.
- Host model and controller extension blocks registered on `RecordingStudioAgents.configuration.hooks` are no longer applied. Move that behavior into the host.
- Do not request the engine root path. ChatKit remains `POST .../chatkit` on the mount.
- v0.8.0 minor bump proposed; do not tag until Marikit confirms.

## [0.7.0] - 2026-10-27

### Changed
- Require Recording Studio `>= 6.1.0` and Flatpack `>= 0.1.315`. The dummy pins Recording Studio `v6.1.0` and Flatpack commit `1fcbafe94f8eb118f0a22182f63f5110fcc97a56` (version 0.1.319). `view_component` is `>= 4.14`, `< 5`, and this repository locks `4.19.0`.
- `RecordingStudioAgents::Configuration#layout` chooses the page shell. `nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`. `false` skips the layout. A string is a layout name. A callable is invoked as `call(controller:)`. Other values raise `ArgumentError`.
- Engine controllers call `recording_studio_layout`. `ChatkitController` sets `layout false` so JSON and server-sent events stay unwrapped.
- The default template reads `content_for :title` and `content_for :subtitle` for the single page heading. Back and close use `flat_pack_page_nav`. Page actions use `register_page_nav`.

### Upgrade notes
- No database migration.
- A host on Recording Studio 4 cannot install this version. Move the host to `v6.1.0` and Flatpack `>= 0.1.315` first.
- Remove `include RecordingStudio::UsesDefaultLayout`, `layout "recording_studio/default_layout"`, `recording_studio_page_nav`, and page-level `FlatPack::PageTitle` calls. Set `content_for :title` instead. The default layout calls `strip` on that slot, so pass the raw text with `html_safe` and let `PageTitle` escape it once. Card `style:` is gone. Use `background:`, `border:`, and `shadow:`.
- Sibling releases of Recording Studio AI, Metrics, Root Switchable, Users, API, Oauth, MCP, Logs, Site Settings, Attachable, and Cache still require `recording_studio` below 5, including the newest tags checked on 2026-10-27. Accessible `v0.22.0` and Trashable `v0.12.0` allow 6.1.0. This repository keeps its existing dummy pins and loads `test/support/widen_recording_studio_requirement.rb` from the Gemfiles. That file is not part of the installed gem. A host that bundles one of those older gems has to widen `recording_studio` the same way.
- Site Settings `v0.5.1` still includes the removed `UsesDefaultLayout` module. Define an empty module before that controller loads. Root Switchable `v0.9.5` still passes Flatpack keywords that 0.1.319 rejects. Map `anchor_url` to close, and drop or translate Card `style:`, or upgrade that gem when a release stops passing them.

## [0.6.0] - 2026-10-23

### Changed
- A successful MCP write stores the OAuth client as the Recording Studio event actor and the person who approved the app as `authorized_by_type` and `authorized_by_id`. That covers the generic `update` tool and `agent_chats_create`. Permission checks stay on the access grant. The catalog still uses the grant's `OauthAuthorization` for visibility. On `agent_chats_create`, a client-sent `authorized_by_type`, `authorized_by_id`, or metadata bag is removed before the write, and the stored event keeps the server stamp. On the generic `update` tool those arguments are unknown fields, so the call is refused and writes no event. A successful update stores the same server stamp.
- Hosts need Recording Studio MCP >= 0.22, API >= 0.16, and Oauth >= 0.15.1 for that stamp. This gem does not depend on those gems. An older API keeps the access-grant actor on the event and does not add the metadata keys.

### Added
- Dummy press kits at `/press_kits`, with photos, a scoped chat, and MCP list, show, and update. A content edit rebuilds the show-page sections. A description edit keeps the sections already stored. Attachable stays a dummy Gemfile pin. No host migration.
- Dummy pins MCP `v0.22.0`, API `v0.16.0`, Oauth `v0.15.1`, and Logs `v0.5.0`. Core stays `v4.7.0`.

## [0.5.0] - 2026-10-21

### Added
- Opt-in per-page chats. `recording_studio_agents_chatkit(page_recording:)` sends `page_recording_id`. The server checks that the recording is inside the current workspace and that the actor can view it, then parents new chats there and limits `threads.list` to that parent. Omit it and ChatKit stays workspace-wide.
- MCP `agent_chats_list` and `agent_chats_create` take an optional `parent`. The same workspace and view checks apply. Omit it and both tools stay workspace-wide.
- `chatkit_options:` on the helper, merged over `config.chatkit_options` (a hash or a lambda of controller and purpose). The frame deep-merges that object into `setOptions` and always sets `api` itself. The hash can carry `startScreen`, `theme`, `header`, `composer`, `history`, and `initialThread`. Host options are a JSON object literal, with the same `raw json_escape` as `endpoint` and `domainKey`, so a quote in a prompt stays a quote.
- The dummy app has a workspace chat at `/agent-chat` and a Press kit page chat at `/agent-chat/page`. `Page` includes the agents capability so a page can own a chat. `PressKitPageChat` is the one declaration for that page's scope and start screen.

### Upgrade notes
- No migration.
- The ChatKit frame depends on FlatPack `~> 0.1`. Pin it from GitHub (dummy tag `v0.1.254`), the same source Recording Studio AI already needs. Include this gem's views in the Tailwind build so `h-[min(40rem,calc(100dvh-16rem))]` is compiled.
- Include `RecordingStudio::Capabilities::Agents` on each type that should own a chat. A type without it still cannot parent one.
- Hosts that want a page-scoped embed pass that page's recording as `page_recording:`. The client id is checked again on the server.
- Set `config.chatkit_options` or pass `chatkit_options:` for a start screen, theme, header, composer placeholder, or history. Per-call options override the config. Do not put an `api` key in those options; the gem's endpoint wins. A lambda takes 0, 1, or 2 arguments (none, the controller, or the controller and `config.purpose`). It is not called while the setup notice is showing.
- A parent that cannot hold a chat is a 422. A trashed page, a missing id, and a present non-string id are a 404. MCP create replay still returns the existing chat and ignores `parent`.
- MCP clients can send `parent`. Old clients that omit it are unchanged.

## [0.4.1] - 2026-10-20

### Fixed
- The ChatKit frame script assigns `endpoint` and `domainKey` as JSON string literals. The quotes stay quotes, so the inline script parses and the ChatKit component can load.

### Upgrade notes
- No host change. Upgrade the gem. `recording_studio_agents_chatkit` emits a script the browser can parse.

## [0.4.0] - 2026-10-19

### Added
- A chat stores the instructions it was opened with on the session snapshot. The host default is `config.instructions`. When `config.instructions_override` is `:admin` or `:edit`, a string override is appended after that default with a blank line. The default is `:none`, which rejects a real override. Blank text uses the host default. The cap is `config.max_instructions_length` (4000). ChatKit does not accept `instructions`. MCP `agent_chats_create` and `Sessions::Create` can pass it when the host opts in. A repeated create key returns the existing chat and does not check a new override. Later turns keep the provider session, so instructions are not stored again per message. The stored copy is personal data, and the 30-day cleanup deletes it with the chat.

### Changed
- ChatKit readiness asks for the OpenAI API key only when the hosted-agent provider is OpenAI and neither `openai_api_key` nor `openai_client` is set. A provider with no hosted-agent model reports `:hosted_agent_unsupported`. An unknown provider gets a generic setup message.

### Fixed
- Creating a chat uses a savepoint, so a rescued idempotency clash does not abort the surrounding transaction.
- An MCP idempotency clash says `conflict` in the error message. Recording Studio MCP `v0.19.1` shows that message and does not show error details.

### Upgrade notes
- ChatKit still needs `config.chatkit_domain_key`. It needs the OpenAI API key only when the configured provider is OpenAI, that provider has a hosted-agent model, and no OpenAI client is injected. `config.provider` is stripped and downcased, and a blank value becomes nil, so ChatKit and session create see the same name. The TypeSafe label stays because Recording Studio AI `v0.15.1` defines `config.typesafe_api_key` in `lib/recording_studio_ai/configuration.rb`. Readiness only treats that provider as ready when the default profile lists a hosted-agent model for it. A provider without one, including Gemini on Recording Studio AI `v0.15.1`, is reported as unsupported instead of being asked for a key.
- Run `add_instructions_to_recording_studio_agents_sessions` before booting servers that read or write `recording_studio_agents_sessions.instructions`. It adds a nullable text column, takes a 5 second `lock_timeout` only for that add, then restores the previous value. There is no default and no backfill, so the table is not rewritten. `down` drops the column.
- `config.instructions_override` defaults to `:none`. Set `:admin` or `:edit` to allow an override. An override is appended after the host default. There is no replace mode.
- `config.max_instructions_length` defaults to 4000. A longer override is rejected.
- The engine adds an exact `instructions` parameter filter. The chat record filters its own `instructions` attribute. A host field such as `shipping_instructions` is not filtered.

## [0.3.0] - 2026-10-19

### Added
- MCP tools for chats and items, registered with Recording Studio API so Recording Studio MCP can advertise them. The `agent-chats` skill is registered when MCP is loaded.
- Dummy host mounts Recording Studio Users, Oauth, API, and MCP. ChatKit still uses the session. MCP uses an Oauth bearer token.

### Changed
- The dummy request root is the workspace selected through Root Switchable.
- `create_idempotency_key` is unique per root (`root_recording_id` + key). The same key in another root creates another chat. Item idempotency keys follow the same rule.
- `Binding` and `Item` copy `root_recording_id` from the recording before validation.
- MCP chat tools call `access_grant.authorize!` (`:view` for reads, `:edit` for writes). A missing grant raises `Sessions::AccessDeniedError`, which MCP maps to `RecordingStudioApi::AuthorizationError`.
- ChatKit `find!` returns 404 when the actor cannot view the chat, so a refused workspace does not reveal that the chat exists.

### Upgrade notes
- Pin Recording Studio Users `v0.24.0`, Oauth `v0.12.5`, MCP `v0.19.1`, and API `v0.11.4` by git tag. Oauth needs Flatpack `~> 0.1.198` (dummy uses `v0.1.254`). Admin is `v2.3.3`. Metrics stays `v0.3.1` because newer MCP, Root Switchable, and Trashable releases require metrics `< 0.4`.
- Mount API, Oauth, and MCP, allow `RecordingStudioOauth::OauthAuthorization` as an access actor, and point `request_root` at `RecordingStudio::RootSwitchable.resolve_current_root`.
- A and B can run back to back. `db:migrate` runs both. Migration A, `scope_agents_idempotency_keys_to_root`, adds a nullable `root_recording_id`, installs a `BEFORE INSERT` trigger that copies the recording's root when the new row leaves it null, backfills existing rows by id, and creates the `(root_recording_id, key)` indexes. It leaves the old global unique indexes in place. Migration B, `require_agents_root_on_idempotency_keys`, backfills again, validates the foreign keys, sets `NOT NULL`, and only then drops the old global unique indexes. The trigger stays after B, so an old app server can still insert: the trigger fills the column before the `NOT NULL` check. Drop the trigger in a later release, after every server writes `root_recording_id` itself. A and B set `lock_timeout` to 5 seconds for the short locks only, then restore the previous value. Concurrent index builds and drops are outside that limit. If a short statement times out, re-run that migration. A row whose recording has no root makes the backfill raise with the remaining count, the recording ids, and a repair hint. `lock_timeout` is restored when that raise happens. `DROP TRIGGER` and `CREATE TRIGGER` run in one transaction. While the old global index still exists, a key already stored in another workspace raises `KeyConflictError`. MCP maps that to `RecordingStudioApi::InvalidActionInputError` (API `v0.11.4` has no conflict error) and still maps a missing chat to `NotFoundError`. The old-index check caches only a miss, so a process that saw the index before B does not keep rejecting a key after B drops it. A same-root create that loses the per-root unique index returns the chat that won. `schema.rb` does not dump the fill trigger. A later migration that drops it must use `DROP TRIGGER IF EXISTS`. B will not drop the old indexes unless the new ones are valid. B's `down` raises `ActiveRecord::IrreversibleMigration` because the global unique indexes cannot be restored once the same key exists in two workspaces. Recording ids are unchanged.
- Set `request_actor` from the session for ChatKit. MCP reads the bearer token's access grant and does not use the browser switcher.

## [0.2.0] - 2026-10-17

### Added
- ChatKit `POST /chatkit` endpoint. It speaks the ChatKit thread protocol over JSON and server-sent events, checks Accessible access, and calls Sessions services plus Recording Studio AI. The first turn is read from the provider stream, and from saved items when that stream has no text, because create is not streamed.
- `recording_studio_agents_chatkit` renders the official `<openai-chatkit>` component against that endpoint, with the session cookie, CSRF token, and `config.chatkit_domain_key`. When `OPENAI_API_KEY` or `CHATKIT_DOMAIN_KEY` is missing, it renders a setup notice.

### Upgrade notes
- Set `request_actor` and `request_root` so the endpoint can resolve the signed-in actor and the root.
- Set `config.openai_api_key` from `OPENAI_API_KEY` or Rails credentials through Recording Studio AI.
- Register the page origin in the OpenAI domain allowlist and set `config.chatkit_domain_key` from `CHATKIT_DOMAIN_KEY`.

## [0.1.0] - 2026-10-17

### Added
- `Session` recordable ("Chat") registered under the `:agents` capability.
- `Binding` and `Item` tables for provider session identity, retention, and the local item projection.
- `Sessions::Create`, `Append`, `Rename`, and `Close`. Close deletes the provider session through Recording Studio AI and treats an already-gone session as success. User actions require Accessible edit access on the chat, inherited from the parent. Create does not write a per-chat grant.
- Idempotent `Sessions::Expire` and `ExpireSessionsJob`. Expiry closes by recording and root and does not require the creator's access.
- Recording Studio `~> 4.7` and Recording Studio AI `~> 0.15.1`. Recording Studio AI 0.15.1 rejects a provider session whose runs belong to another root.

### Upgrade notes
- Point host Gemfiles at Recording Studio `v4.7.0`, Recording Studio AI `v0.15.1`, and Recording Studio Metrics `v0.3.1`.
- Run `bin/rails generate recording_studio_agents:migrations`, then `bin/rails db:migrate`.
- Include `RecordingStudio::Capabilities::Agents.to` on each parent type that may own a chat, and add `RecordingStudioAgents::Session` to `config.recordable_types`.
- Schedule `RecordingStudioAgents::ExpireSessionsJob`.
