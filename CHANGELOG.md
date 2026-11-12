# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.11.0] - 2026-11-11

### Added
- In-process Recording Studio MCP tools on a new ChatKit session, when MCP and API are both loaded. The signed-in person's read and write tools are sent as function tools. Each call runs through `RecordingStudioMcp::Dispatcher` on that person's Accessible grant, then goes back with `submit_tool_results`. `config.mcp_tools` defaults to `:write`. `:read` keeps read-only tools. `:off` sends none. The tools this gem registers are not sent. A host without MCP sends no tools. Calls are written to the MCP usage log, share the API read and write rate limits, and stop when API access is disabled. A dropped stream answers pending tool calls. A timed-out result post re-reads the pending calls before it retries. One turn runs at most 8 tool rounds, then refuses the next call. If the run is still waiting, it is cancelled and the chat shows a failure.
- Global ChatKit popup at `GET /recording_studio_agents/popup`. It renders `recording_studio_agents_chatkit` in a bare layout that fills a frame, using `config.request_root` and no page scope. It is a same-site page. Sign in uses `target: "_top"`.
- `recording_studio_agents_launcher` renders a FlatPack `FloatingFrame` (FlatPack `>= 0.1.354`) that opens that popup. It sits at the bottom left with `padding: :none`. The iframe sandbox is `allow-scripts allow-same-origin allow-forms allow-popups allow-top-navigation-by-user-activation`, and `allow` is `clipboard-write`. `label`, `title`, and `position` can be overridden. `config.launcher` defaults to on. `false` renders nothing. The helper does not change the session cookie. Framing stays on the same site.
- The install generator sets `config.request_actor` and `config.request_root`. The actor uses `current_user` when the controller has it, then the host session. The root is Root Switchable's current workspace.
- A content security policy on that action only: ChatKit script, connect, and frame hosts, plus `frame-ancestors 'self'` and `config.chatkit_allowed_origins`. The ChatKit setup script is the asset `recording_studio_agents/chatkit.js`, served from `'self'`. Per-render config is data attributes, not inline JavaScript. `script-src` does not include `'unsafe-inline'` and does not need a CSP nonce. When `asset_host` makes that script absolute, its origin is added to `script-src`. A relative script stays covered by `'self'`. `X-Frame-Options` is dropped on that response. Other pages keep the app policy.
- `config.chatkit_allowed_origins`. Development and test default to `http://localhost:3000` and `http://127.0.0.1:3000`. Other environments default to an empty list, so a missing `CHATKIT_ALLOWED_ORIGINS` leaves `frame-ancestors` at `'self'`. `config.chatkit_domain_key` still comes from `CHATKIT_DOMAIN_KEY`.
- `config.popup_stylesheet`, default `tailwind`. The popup layout loads that asset. Set it to `nil` to skip the tag.
- Same-site framing only. The popup uses the host session cookie and Rails `protect_from_forgery`. It does not change that cookie. Cross-site framing is not supported. A later opt-in would be owned by the host's session config.
- A sign-in prompt for signed-out visitors. `config.sign_in_path` defaults to `main_app.new_user_session_path` when that route exists, otherwise `/users/sign_in`. English and French copy.
- A signed-in visitor with no workspace sees an empty state instead of the chat.
- `POST /chatkit` returns 401 when no actor is signed in, and 403 when execute is denied.

### Changed
- A new chat sends `config.provider` to Recording Studio AI only when that name is listed in `allowed_provider_overrides`. The default `openai` stays for ChatKit readiness. Recording Studio AI treats a provider argument as an override, and the default is not one, so a chat no longer fails with "Provider override openai is not enabled".
- A known Recording Studio API error from a tool call is logged and returned as an error result. Any other error propagates. The API-enabled check and the rate limiter only rescue database and Redis failures, and they log those.
- The dummy pins Recording Studio API `v0.21.2`, with MCP `v0.31.0`, Oauth `v0.21.5`, Moveable `v4.1.0`, Icons `v0.2.0`, and FlatPack `v0.1.354`. API 0.20 records the access-grant actor on a resource update. An in-process chat tool grant already names the signed-in person as that actor and does not set an API client, so the event actor is that person and there is no impersonator. `authorized_by` is still that person. An older API leaves this event actor empty. API 0.21.2 keys that same grant's create idempotency and list cursor as `actor:<Type>:<id>`. A grant with neither an API client nor an actor raises `AuthorizationError`. The chat still passes `idempotency_key: call_id`.
- Popup asset origins go through `ChatkitHostSettings.origin`, the same parser as `config.chatkit_allowed_origins`.
- `ChatToolLimit` copies Recording Studio API's private rate-limit key layout (`namespace:api_read|api_write:identifier:window`) and its increment script. Replace it with a public API limiter when one exists.
- At boot, when `config.mcp_tools` is `:write` and the installed `recording_studio_api` is older than 0.20, the gem logs a warning that `event.actor` will be empty for agent writes and that the host should upgrade. It does not raise. `:read` and `:off` skip the warning. The root Gemfile pins FlatPack tag `v0.1.354`, matching the dummy. The gemspec requires FlatPack `>= 0.1.354` for `FloatingFrame`.

### Upgrade notes
- No database migration.
- `recording_studio_ai` is `~> 0.20.0`. The dummy pins GitHub tag `v0.20.0`.
- In-process tool writes record the signed-in person as `event.actor` when the host API is 0.20 or later. The dummy pins API `v0.21.2`. The grant does not mint an API client. `authorized_by` stays that person. Hosts on an older API still store `authorized_by` and leave the event actor empty. Boot logs a warning in that case when `config.mcp_tools` is `:write`. It does not raise. On API 0.21.2, a create with no API client is stored as `actor:<Type>:<id>`, and a grant with neither a client nor an actor raises `AuthorizationError`. MCP 0.31 writes a usage log that needs the Logs aggregation-runs table. Install it with the Logs 0.7.1 migrations if it is not already there.
- Hosts that already load Recording Studio MCP start sending workspace tools on new chats. Set `config.mcp_tools = :off` to keep the previous chat, or `:read` to allow reads only. Writes run as the signed-in person.
- Hosts that need to force a provider on a new chat add that name to Recording Studio AI `config.allowed_provider_overrides`. Leaving the list empty keeps the profile's model.
- If `authorization_handler` is not set, use `RecordingStudioAI::AccessibleAuthorization`. It maps `recording_studio_ai.execute` to `:edit` on the workspace through Accessible. Do not set a handler that allows every signed-in person.
- Call `recording_studio_agents_launcher` from the host layout. It needs FlatPack `>= 0.1.354`. It opens `recording_studio_agents.popup_path` on the same site and does not change the host session cookie. A later opt-in for cross-site framing would be owned by the host's session config. Sign in uses `target: "_top"`. The launcher sandbox includes `allow-top-navigation-by-user-activation`. Set `config.launcher = false` to render nothing. Pass `label:`, `title:`, or `position:` to change the defaults (`"Open chat"`, `"Chat"`, `:bottom_left`).
- Run the install generator again, or copy `request_actor` and `request_root` from the initializer template. ChatKit and the popup stay empty until both are set.
- Add staging and production origins with `config.chatkit_allowed_origins` or `CHATKIT_ALLOWED_ORIGINS`, and register those origins on the OpenAI domain allowlist. Leave the list unset outside development and the popup only allows `'self'` to frame it.
- Set `config.sign_in_path` when the host sign-in path is not Devise's `new_user_session_path`.
- Set `config.popup_stylesheet` when the host Tailwind asset is not named `tailwind`.

## [0.10.0] - 2026-11-11

### Added
- Agent chat MCP endpoints (`agent_chats_list`, `agent_chats_create`, `agent_chats_read`,
  `agent_chats_append`, `agent_items_list`, `agent_items_read`) declare an OpenAPI
  success `responses` entry with a JSON schema and a sample `example`. Recording Studio
  MCP 0.29.0 copies that schema into each tool's `outputSchema`, so the MCP docs page
  can show sample output. The schemas match the hashes the handlers already return.
  Request handling is unchanged.

### Host upgrade notes
- No migration and no runtime behavior change. Hosts that want sample output in MCP
  docs need Recording Studio MCP 0.29.0 once it ships. This gem does not depend on that
  MCP version.

## [0.9.1] - 2026-11-05

### Changed
- Lock Rails at `8.1.4.1` in the gem and dummy lockfiles, with rack `3.2.8`, nokogiri `1.19.7`, loofah `2.25.3`, and rails-html-sanitizer `1.7.2`. Dummy `net-ssh` stays `7.3.8`. Bundler also pulled `io-console` `0.9.5` and `rack-test` `2.3.0`.

### Host upgrade notes
- No API or migration change. Hosts should `bundle update rails rack nokogiri loofah rails-html-sanitizer` (and `net-ssh` if locked) to the same floors. Do not tag this version until the PR merges.

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
