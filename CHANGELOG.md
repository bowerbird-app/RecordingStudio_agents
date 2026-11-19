# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.20.0] - 2026-11-19

### Changed
- Root and dummy Gemfiles pin Recording Studio `~> 7.8` (`v7.8.0`), FlatPack `~> 0.2` (`v0.2.0`), Recording Studio AI `~> 0.26` (`v0.26.0`), API `~> 1.21` (`v1.21.2`), Accessible `~> 0.58` (`v0.58.0`), Icons `~> 0.5` (`v0.5.0`), Logs `~> 0.9` (`v0.9.0`), Metrics `~> 0.10` (`v0.10.0`), Moveable `~> 6.1` (`v6.1.0`), and Trashable `~> 1.3` (`v1.3.0`).
- Dummy-only pins: Admin `~> 2.20` (`v2.20.0`), Attachable `~> 0.34` (`v0.34.0`, `require: false`), Cache `~> 0.8` (`v0.8.0`), and Root Switchable `~> 0.17` (`v0.17.0`). Users stays `v0.37.0`. Oauth stays `v0.25.1`. MCP stays `v0.39.2`. Site Settings stays `v0.6.0`.
- The dummy drops the `flat_pack/heroicons` importmap pin and the `flat-pack--icon` controller registration. Launcher icons are the server-rendered SVG.
- Gemspec floors are unchanged.

### Upgrade notes
- Hosts MUST run the Recording Studio 7.4, 7.5 and 7.7 migrations if they have not.
- flat_pack 0.2.0 is supported; hosts moving to 0.2 must remove the manual `flat_pack/heroicons` importmap pin and any `flat-pack--icon` controller registration.
- [Compare v0.19.0...v0.20.0](https://github.com/bowerbird-app/RecordingStudio_agents/compare/v0.19.0...v0.20.0)

## [0.19.0] - 2026-11-19

### Added
- `config.enabled` turns agent chats off for the whole site. It defaults to `true`. It accepts `true`, `false`, or a lambda. The lambda is called on every check. It can take the controller, or no argument. A service or an MCP tool passes `nil`. A lambda that raises is off, and the log line is the error class only. While chats are off, the launcher and the chat frame render nothing, every engine route responds 404 (including a POST with no CSRF token), `Sessions::Create` and `Sessions::Append` raise `RecordingStudioAgents::DisabledError` before the provider is called, and the agent chat tools return not found. `ExpireSessionsJob` still closes expired chats. `config.launcher = true` does not turn any of that back on.

### Upgrade notes
- No migration and no host setting. The default is on, so an existing app behaves as before. Set `config.enabled` or `enabled:` in `config/recording_studio_agents.yml` to turn chats off. A boolean taken from an environment variable is read at boot, so restart the process after changing it.
- [Compare v0.18.7...v0.19.0](https://github.com/bowerbird-app/RecordingStudio_agents/compare/v0.18.7...v0.19.0)

## [0.18.7] - 2026-11-19

### Changed
- The recording index checks access once per index. It keeps rows from `RecordingStudioAccessible.authorized_recordings` for that root instead of calling `authorized?` on each recording. A root grant is `Recording.within`. A narrower grant stays the seeded set, so a recording outside it, and a child nested under that recording, stay out.
- Root and dummy Gemfiles pin release tags. Recording Studio is `v7.7.2` and Recording Studio AI is `v0.25.3` (within `~> 0.25`). FlatPack stays on `v0.1.380`. API is `v1.19.0` in both Gemfiles. Accessible is `v0.55.0`, Icons `v0.4.2`, Logs `v0.8.2`, Metrics `v0.9.2`, Moveable `v6.0.3`, and Trashable `v1.2.3`.
- Dummy-only tags: Root Switchable `v0.16.1`, Users `v0.37.0`, Oauth `v0.25.1`, MCP `v0.39.2`, Admin `v2.19.1`, Attachable `v0.33.2`, and Cache `v0.7.1`. Site Settings stays `v0.6.0`.
- `view_component` is `~> 4.19` and Puma is `~> 8.1`.

### Upgrade notes
- No migration for the index change. A child of a recording the actor can view stays listed. A child under a recording they cannot view stays out.
- Hosts MUST run the Recording Studio 7.4, 7.5, and 7.7 migrations. This gem does not copy them. Fresh installs get the same changes from Recording Studio `db/install_migrate`.
- API 1.19 needs `config/recording_studio_api.yml` and the API client owner migration. Users 0.37 needs the sign-in lockout and sign-in link migrations. Recording Studio AI 0.25.3 adds migration `20261118120000`.
- [Compare v0.18.6...v0.18.7](https://github.com/bowerbird-app/RecordingStudio_agents/compare/v0.18.6...v0.18.7)

## [0.18.6] - 2026-11-18

### Changed
- The gem-owned preamble tells the model to say a change is done only after a write tool returned success in this turn. Otherwise it calls the tool, or asks if something is unclear. A result from an earlier turn does not count. The line is part of the instructions sent when the hosted session is created. `threads.add_user_message` stays on that session, so later turns keep the same instructions. A text-only reply does not run a tool and does not change a recording.

### Upgrade notes
- No migration and no host setting. A chat opened before this release keeps the instructions stored for that hosted session. A new chat gets the extra line.

## [0.18.5] - 2026-11-18

### Added
- Each ChatKit turn sends a recording index in the model input, on create and on append. The index lists the current page, its parent, its viewable siblings and children, and nearby recordings in the same root. Each entry is `id`, `type`, and, when the type is mapped, `name`. At most 25 entries, and the JSON stays within 4096 bytes.
- `config.recording_names` maps a recordable class name to the column used as its display name. The default maps `RecordingStudioAgents::Session` to `title`. A type that is not in the map is listed as type and id only.

### Changed
- The `page_context` timing line adds `index_n=` (entries sent) and `index_ms=` (time to build the index). The line still leaves out names, message text, and tool arguments.

### Upgrade notes
- No migration. Set `config.recording_names` to the columns your recordables use (`"Page" => "title"`, `"PressKit" => "name"`). An unmapped type contributes no title. Access rows are left out.
- The index is untrusted data. Titles are user content. Write tools are still checked with Recording Studio and Accessible when the call runs.
- Log collectors see `index_n=` and `index_ms=` on `phase=page_context`.

## [0.18.4] - 2026-11-18

### Changed
- ChatKit timing lines include `q=` and `db=` for the SQL in that phase. Schema and cached statements are left out. A new chat logs `create_tools`, `create_provider` (with `tools=`, a count), and `create_persist`. `model_stream` times the first provider read until it returns tool calls or ends. A round line adds `answers_ms=` and `model_ms=`. `total` adds `dropped=` when a replay was dropped.
- One chat turn builds the actor's tool grant and tool surface once and reuses them for the write cap, the audit kind, and each tool call. A write still goes through Recording Studio and Accessible when it runs.
- `threads.list` pages in SQL by `created_at` descending, then `id` descending. It authorizes the fetched rows and keeps reading when a row is not viewable, so a page is not short while more viewable chats exist. The 50 cap, `has_more`, `after`, and page-parent filter stay.
- A dropped assistant replay logs `[recording_studio_agents.chatkit] dedupe dropped item_id=<id|none> by=<id|text>`. The line has no message text.

### Upgrade notes
- No migration and no host setting. Tool permissions, limits, and audit rows are unchanged. A grant revoked during a turn still cannot write.
- Log collectors see `q=`, `db=`, the split create phases, `model_stream`, `answers_ms=`, `model_ms=`, and the dedupe line. The lines still leave out message text, tool arguments, tool results, and secrets.

## [0.18.3] - 2026-11-18

### Fixed
- ChatKit shows one copy of an assistant message that the provider sends again in the same turn. After a tool round, a hosted read can repeat the message as `message_completed` with no text deltas. That repeat is dropped when it is the same provider item id and the same text, or when it has no item id and the text matches a message already shown in this turn. Text deltas are kept. A different item id, different text, or the same text on the next turn is shown. A dropped repeat adds no bubble, no thread event, and no item.

### Changed
- Require Recording Studio `~> 7.7` and Recording Studio AI `~> 0.25`. The root and dummy Gemfiles use those ranges. Lockfiles resolve Recording Studio 7.7.1 and Recording Studio AI 0.25.1.
- The dummy app does not copy the Recording Studio 7.4, 7.5, or 7.7 migrations.

### Upgrade notes
- Install Recording Studio `~> 7.7` (`7.7.1` or newer, below `7.8`) and Recording Studio AI `~> 0.25` (`0.25.1` or newer, below `0.26`). This gem has no migration.
- Host apps run the Recording Studio 7.4, 7.5, and 7.7 migrations themselves. Fresh installs get the same changes from Recording Studio's `db/install_migrate`.
- A repeated assistant line in one turn is shown once. The next turn still shows that line when the person asks again.

## [0.18.2] - 2026-11-17

### Changed
- `threads.create` and `threads.add_user_message` write the opening server-sent events before the chat is saved and before the provider runs. A new thread sends `thread.created`, then the user message, then `stream_options`. A reply sends the user message, then `stream_options`. The thread id and the user item id are chosen first and stored on the rows that follow, so a refresh shows the same thread and the same message.
- A `usage_declined` error still sends the out-of-credits notice and stores nothing. The log line is unchanged. An unsafe out-of-credits URL still raises, and that failure is an error event on the same stream. The event and the log leave the URL out.
- A provider contract error, or another chat error, raised while saving that turn is an error event on the same stream. The object is still `type`, `code` `custom`, `message`, and `allow_retry` `false`. The stream has already started, so the HTTP status is `200`. Invalid JSON, a rejected page, a missing thread, and a signed-out request stay JSON responses.
- ChatKit requests log one timing line per phase under `[recording_studio_agents.chatkit]`. The phases are `page_context`, `create` or `append`, `ttft` (request start until the first assistant text delta is written), `tool` (with `name=`), `round` (with `n=`), and `total`. Each line includes `ms=` and `type=` when the request type is a short token. The lines use a monotonic clock. They do not include message text, tool arguments, tool results, page context, tokens, headers, or secrets.

### Upgrade notes
- No migration and no host setting. The happy-path event order is unchanged, and those events now leave the server before the provider call.
- Code that treated a contract error from `threads.create` or `threads.add_user_message` as an HTTP `400` or `403` JSON body should read the error event on the `200` stream instead. The message is the same. Nothing from that failed turn is stored.
- Log collectors will see the new `timing` lines.

## [0.18.1] - 2026-11-17

### Changed
- MCP descriptions for `agent_chats_list`, `agent_chats_create`, `agent_chats_read`, `agent_chats_append`, `agent_items_list`, and `agent_items_read` say what the call does, which other tool to use, where each id comes from, and the fields that come back. Path arguments no longer use the filler "Path parameter".

### Upgrade notes
- No host change. Tool names, arguments, access checks, and results are unchanged.

## [0.18.0] - 2026-11-17

### Added
- `config.out_of_credits_url` (a string or a lambda that receives `request:` and `root_recording:`) and `config.out_of_credits_label`. `nil` for the URL leaves the notice without a link. `nil` for the label uses the locale string.

### Changed
- Require Recording Studio AI `~> 0.24`. The root and dummy Gemfiles pin tag `v0.24.0`.
- `RecordingStudioAI::Errors::UsageDeclined` (`usage_declined`) during `threads.create` or `threads.add_user_message` is a `200` server-sent stream. The person's message stays on screen, then an assistant line says it was not sent. Neither line is stored. A refresh does not show them. A new chat uses a transient thread id that is not a recording id, so `threads.get_by_id` cannot load it. The same notice is sent when the decline arrives after the stream has started. Other contract errors stay JSON errors. The Rails log line for the decline is unchanged.

### Upgrade notes
- Install Recording Studio AI `~> 0.24` (`v0.24.0` or newer, below `1.0`). This gem has no migration.
- Set `config.out_of_credits_url` to an `http` or `https` URL, or to a path such as `"/billing"`. A path is joined to the request origin because the ChatKit frame is not the host. ChatKit opens that link in a new tab. An unsafe URL, including `javascript:`, raises. Leave the setting `nil` for a notice without a link.
- Set `config.out_of_credits_label` to replace the link text. `nil` keeps the translation (`Add credits` in English, `Ajouter des crédits` in French).

## [0.17.0] - 2026-11-17

### Changed
- `recording_studio_agents_launcher` renders nothing when `config.request_actor` or `config.request_root` returns nothing. ChatKit and the popup use those same resolvers.
- `config.launcher` accepts `true`, `false`, or a lambda that takes the controller. The lambda runs on each render, after the actor and workspace checks. Any other value raises.

### Upgrade notes
- A page with no signed-in person, or a signed-in person with no workspace, no longer shows the launcher. Set `config.launcher` to a lambda when it should also stay off on some pages that have both.

## [0.16.1] - 2026-11-17

### Changed
- Rescued errors on the ChatKit request are written to the Rails log. The line starts with `[recording_studio_agents.chatkit]`, then the rescue site, the error class, `code=` when the error has one, the message, and `type=` when the ChatKit request type is a short token. Client disconnects are info. Other rescued errors are warnings. JSON parse errors leave out the quoted source fragment. The HTTP status, JSON body, and server-sent events are unchanged.

### Upgrade notes
- No host change. Log collectors that watch Rails will see these lines. The line does not include the request body, headers, cookies, or credentials.

## [0.16.0] - 2026-11-17

### Removed
- Removed the agent-chats MCP skill; tool and field descriptions now carry the idempotency rule.

### Changed
- Dummy GitHub pins move to the latest release tags: Recording Studio `v7.3.0`, FlatPack `v0.1.377`, Accessible `v0.45.1`, Trashable `v1.0.1`, Users `v0.32.0`, API `v1.2.1`, Oauth `v0.25.0`, MCP `v0.35.0`, Moveable `v6.0.0`, Icons `v0.4.0`, Admin `v2.18.0`, Site Settings `v0.6.0`, Attachable `v0.31.0`, and Cache `v0.7.0`. The root FlatPack pin is `v0.1.377`. AI, Metrics, Logs, and Root Switchable stay on their current tags.

## [0.15.0] - 2026-11-16

### Changed
- Require Recording Studio `>= 7.0.0, < 8.0`, Recording Studio AI `>= 0.22.0, < 2.0`, and Recording Studio API `>= 0.26.0, < 2.0`. The four chat `:id` endpoints register `recordable_type: "RecordingStudioAgents::Session"`. Read, append, and item handlers authorize that chat (`:view` to read, `:edit` to append). HTTP requests use `context.recording`. MCP 0.33 leaves that field empty, so the handler resolves the same scoped recording with `ScopedRecording.find!` when it is absent.
- Dummy API pin is `v0.26.0`. API `1.1.0` needs Recording Studio `>= 7.1`, and the newest MCP and Attachable releases still require API `< 1.0`, so 1.x does not install on this core 7.0 dummy. Attachable moves to `v0.28.0` and the dummy FlatPack pin moves to `v0.1.376` so Bundler can resolve API 0.26. Users `v0.31.0` still registers `users/:id` without `scope_id: false`, so the dummy initializer opts that user-id path out of recording scope and the dummy can boot.

## [0.14.0] - 2026-11-16

### Added
- The chat popup takes the host page it was opened on. When the panel opens, and on every Turbo visit, `recording_studio_agents/launcher.js` posts the page to the popup iframe with `postMessage` and `window.location.origin` as the target. The message is the current URL, `document.title`, the selected text (capped), an optional page id, and optional host metadata. The popup keeps the latest message from its own origin and its parent frame, and sends that data on the next `POST /chatkit` in the `X-Recording-Studio-Agents-Page` header. The server checks and caps every field. A page id is used only when the signed-in person can view it through Accessible. A visible page parents a new chat. The same data is a server-built preface on the model input for that turn. The stored message stays the person's words. An open thread is left in place when the page changes. The next turn of that thread gets the new preface.
- `config.launcher_icon` (default `:chat`), `config.launcher_label` (default `"Open chat"`), and `config.popup_title` (default `"Chat"`). A call to `recording_studio_agents_launcher` can still pass `icon:`, `label:`, and `title:`.

### Changed
- The popup chat is the height of its iframe. The popup document does not scroll, on desktop or on a phone. ChatKit keeps the composer at the bottom of that box and scrolls the messages.

### Upgrade notes
- No migration. Hosts that render `recording_studio_agents_launcher` start sending page context. Set the page id with `data-recording-studio-agents-page-recording-id` or `<meta name="recording-studio-agents-page-recording-id">`. Set metadata with `data-recording-studio-agents-page-metadata` as a small JSON object. Do not send an `instructions` field. The client posts data, and the server writes the preface. Framing and the session cookie are unchanged.
- Launcher defaults match the previous button and the previous "Chat" heading, so an existing host sees the same chrome. Set `config.launcher_icon`, `config.launcher_label`, or `config.popup_title` to change them. Setting `popup_title` also replaces the translated popup document title.

## [0.13.0] - 2026-11-15

### Changed
- Require Recording Studio `>= 7.0, < 8.0`. The root and dummy Gemfiles pin GitHub tag `v7.0.0`.
- Require Recording Studio AI `>= 0.22.0, < 1.0` and Recording Studio API `>= 0.24.0, < 1.0`.
- Dummy pins that cannot install on core 7 move to the known-good tags: AI `v0.22.0`, API `v0.24.0`, Accessible `v0.44.0`, Trashable `v0.17.0`, Root Switchable `v0.16.0`, Moveable `v5.0.0`, Admin `v2.16.0`, Metrics `v0.9.0`, Logs `v0.8.0`, and Users `v0.30.0`. MCP `v0.33.3` and Oauth `v0.21.9` open the core constraint that `v0.33.2` and `v0.21.7` locked to `~> 6.0`.
- `root_recording_for` is find-only. Seeds and tests create roots with `create_root_recording!(recordable, actor:)`. The dummy keeps a simple `config.authorize_write` callback. Trashable 0.17 seed lookups use `Recording.kept`.

## [0.12.2] - 2026-11-15

### Changed
- Dummy lockfile updates `omniauth` from `2.1.4` to `2.2.0`, the lowest release that patches CVE-2026-63183. The root bundle does not depend on `omniauth`.

## [0.12.1] - 2026-11-15

### Changed
- Allow recording_studio < 8.0 (core 7 phase 1)

## [0.12.0] - 2026-11-14

### Changed
- Require Recording Studio `~> 6.0, >= 6.12.0`. The root and dummy Gemfiles pin GitHub tag `v6.12.0`.
- Closing a chat loads `recording.recordables(all: true)` and deletes every session snapshot. Core 6.12 returns 50 events from `recordables` unless `all: true`.
- Recording Studio 6.9 requires `recording_studio_events.root_recording_id`. Copy `AddRootRecordingIdToRecordingStudioEvents` and run `bin/rails db:migrate`.

## [0.11.1] - 2026-11-13

### Changed
- Dummy and root Gemfiles pin the current Recording Studio ecosystem GitHub release tags: Recording Studio `v6.7.0`, FlatPack `v0.1.356`, API `v0.23.0`, Accessible `v0.32.0`, Trashable `v0.14.0`, Icons `v0.2.1`, Moveable `v4.1.1`, Logs `v0.7.4`, Metrics `v0.8.0`, Root Switchable `v0.15.0`, Users `v0.28.1`, Oauth `v0.21.7`, MCP `v0.33.2`, Admin `v2.13.0`, Site Settings `v0.5.6`, Attachable `v0.23.0`, and Cache `v0.6.3`. AI stays `v0.21.2`.
- The gemspec requires `recording_studio_api` `>= 0.23.0, < 1.0`. `~> 0.23.0` would refuse later 0.x releases. Attachable `v0.23.0` still requires `~> 0.23`, and `~> 0.22.1` cannot install API `0.23.0`.
- Removed `test/support/widen_recording_studio_requirement.rb`. The pinned gemspecs accept Recording Studio `>= 6.1.0`.
- The dummy sets `config.authorize_write` so Recording Studio 6.5 allows `record!` when an actor is present. Trashable `v0.14.0` adds nullable `purge_at` on recordings. The mounted root switch page still needs an Accessible `:view` grant on the current root.

## [0.11.0] - 2026-11-11

### Added
- Prompt-injection limits for in-process chat tools. A gem-owned preamble is prepended to every chat, before the host instructions and any per-session override, and there is no switch to remove it. Tool output posted back to the model is JSON `{"untrusted_tool_output":"<text>"}`, still capped at 256 KB. `config.mcp_max_writes_per_turn` defaults to 3. The write cap and the 8-round cap follow the provider turn id, so a resumed, recovered, or retried turn counts earlier writes and rounds. The write count, the round number, and the pending insert are taken together under a PostgreSQL advisory lock for that turn, so two calls cannot both pass the cap. The lock method opens that transaction and releases it before the tool runs. A chat tool round must not run inside an open transaction. That raises unless `config.allow_chat_tools_in_transaction` is true. It defaults to false. A second caller with the same call id joins the audit row already started, does not run the tool, and does not change that row. A live duplicate is left out of the results posted to the provider. Dispatch stops at `config.chat_tool_deadline` (default 2 minutes), posts `tool call timed out; it was not re-run`, and stores `unknown` when the pending update wins. A pending row is also stale after that deadline plus a 30 second grace. `config.chat_tool_stale_after` (default 10 minutes) must be longer than the deadline plus that grace. Unknown is posted only when the pending update wins. A round of only live duplicates ends with no ChatKit event. When `config.mcp_tools` is not `:off`, boot reads the database adapter from the connection config without opening a connection. `recording_studio_agents_chat_tool_audits` has a unique index on provider turn id and call id. A later write returns `write limit reached` and the turn continues. Reads are still answered. `config.mcp_tool_allow` and `config.mcp_tool_deny` are tool-name lists, applied when tools are listed and again at call time. Deny wins. An empty allow list blocks every tool. `config.mcp_tools` stays `:write` by default. Each call inserts `recording_studio_agents_chat_tool_audits` as `pending` before the tool runs, then updates the outcome. A crash leaves `pending`. The row stores actor type and id, chat recording id, provider turn id, round number, tool name, read or write, at most 50 identifier-like argument keys of 64 characters, outcome (`pending`, `ok`, `error`, `refused`, `limited`, `unknown`), and call id. Values are not stored.
- In-process Recording Studio MCP tools on a new ChatKit session, when MCP and API are both loaded. The signed-in person's read and write tools are sent as function tools. Each call runs through `RecordingStudioMcp::Dispatcher` on that person's Accessible grant, then goes back with `submit_tool_results`. `config.mcp_tools` defaults to `:write`. `:read` keeps read-only tools. `:off` sends none. The tools this gem registers are not sent. A host without MCP sends no tools. Calls are written to the MCP usage log, share the API read and write rate limits, and stop when API access is disabled. A dropped stream answers pending tool calls. A timed-out result post re-reads the pending calls before it retries. One provider turn runs at most 8 tool rounds, including rounds already recorded when that turn resumes, then refuses the next call. If the run is still waiting, it is cancelled and the chat shows a failure.
- Global ChatKit popup at `GET /recording_studio_agents/popup`. It renders `recording_studio_agents_chatkit` in a bare layout that fills a frame, using `config.request_root` and no page scope. It is a same-site page. Sign in uses `target: "_top"`.
- `recording_studio_agents_launcher` renders a FlatPack `FloatingFrame` (FlatPack `>= 0.1.354`) that opens that popup. It sits at the bottom left with `padding: :none`. The iframe sandbox is `allow-scripts allow-same-origin allow-forms allow-popups allow-top-navigation-by-user-activation`, and `allow` is `clipboard-write`. `label`, `title`, and `position` can be overridden. `config.launcher` defaults to on. `false` renders nothing. The helper does not change the session cookie. Framing stays on the same site.
- The install generator sets `config.request_actor` and `config.request_root`. The actor uses `current_user` when the controller has it, then the host session. The root is Root Switchable's current workspace.
- A content security policy on that action only: ChatKit script, connect, and frame hosts, plus `frame-ancestors 'self'` and `config.chatkit_allowed_origins`. The ChatKit setup script is the asset `recording_studio_agents/chatkit.js`, served from `'self'`. Per-render config is data attributes, not inline JavaScript. `script-src` does not include `'unsafe-inline'` and does not need a CSP nonce. When `asset_host` makes that script absolute, its origin is added to `script-src`. A relative script stays covered by `'self'`. `X-Frame-Options` is dropped on that response. Other pages keep the app policy.
- `config.chatkit_allowed_origins`. Development and test default to `http://localhost:3000` and `http://127.0.0.1:3000`. Other environments default to an empty list, so a missing `CHATKIT_ALLOWED_ORIGINS` leaves `frame-ancestors` at `'self'`. `config.chatkit_domain_key` still comes from `CHATKIT_DOMAIN_KEY`.
- `config.popup_stylesheet`, default `tailwind`. The popup layout loads that asset. Set it to `nil` to skip the tag.
- `config.popup_theme`, default `rounded`. The popup document sets `data-theme` from that value.
- The launcher root is `id="recording_studio_agents_launcher"` with `data-turbo-permanent`, so a Turbo Drive visit keeps the iframe. `recording_studio_agents/launcher.js` opens the panel again after the visit. FlatPack closes that popover on an outside click and marks it closed when the node reconnects.
- Same-site framing only. The popup uses the host session cookie and Rails `protect_from_forgery`. It does not change that cookie. Cross-site framing is not supported. A later opt-in would be owned by the host's session config.
- A sign-in prompt for signed-out visitors. `config.sign_in_path` defaults to `main_app.new_user_session_path` when that route exists, otherwise `/users/sign_in`. English and French copy.
- A signed-in visitor with no workspace sees an empty state instead of the chat.
- `POST /chatkit` returns 401 when no actor is signed in, and 403 when execute is denied.

### Changed
- A new chat sends `config.provider` to Recording Studio AI only when that name is listed in `allowed_provider_overrides`. The default `openai` stays for ChatKit readiness. Recording Studio AI treats a provider argument as an override, and the default is not one, so a chat no longer fails with "Provider override openai is not enabled".
- A known Recording Studio API error from a tool call is logged and returned as an error result. Any other error propagates. The API-enabled check and the rate limiter only rescue database and Redis failures, and they log those.
- The dummy pins Recording Studio API `v0.22.1`, with MCP `v0.33.1`, Oauth `v0.21.6`, Moveable `v4.1.0`, Icons `v0.2.0`, and FlatPack `v0.1.354`. API 0.20 records the access-grant actor on a resource update. An in-process chat tool grant already names the signed-in person as that actor and does not set an API client, so the event actor is that person and there is no impersonator. `authorized_by` is still that person. An older API leaves this event actor empty. API 0.21.2 keys that same grant's create idempotency and list cursor as `actor:<Type>:<id>`. A grant with neither an API client nor an actor raises `AuthorizationError`. The chat still passes `idempotency_key: call_id`.
- Popup asset origins go through `ChatkitHostSettings.origin`, the same parser as `config.chatkit_allowed_origins`.
- The dummy pins MCP `v0.33.1` and Oauth `v0.21.6`. Both allow API `< 0.23` and Recording Studio `>= 6.1.0`. `test/support/widen_recording_studio_requirement.rb` no longer rewrites `recording_studio_api`. It still rewrites `recording_studio` for Accessible, Trashable, Cache, Attachable, Site Settings, and Icons. MCP 0.33.1 ships no migration. `tools/list`, routes, and `Dispatcher` / `UsageCall` stay compatible with this gem. Docs and `describe` titles change inside MCP. `ActorRequired` and `InvalidParent` return tool errors instead of JSON-RPC `-32603`.
- Chat tool rate limits call `RecordingStudioApi::RateLimit.check` with `fail_closed: true`. The key layout stays `{namespace}:{api_read|api_write}:{identifier}:{window}`. A missing Redis or a Redis error limits the call even when the host's fail-closed bucket list is off.
- At boot, when `config.mcp_tools` is `:write` and the installed `recording_studio_api` is older than 0.21.2, the gem logs a warning that in-process creates need 0.21.2 and that the host should upgrade. It does not raise. `:read` and `:off` skip the warning. The root Gemfile pins FlatPack tag `v0.1.354`, matching the dummy. The gemspec requires FlatPack `>= 0.1.354` for `FloatingFrame`.
- `config.launcher` must be `true` or `false`. Any other value raises. The launcher path comes from `RecordingStudioAgents::Engine.routes`, so a host mount name other than `recording_studio_agents` still opens the popup.
- `recording_studio_ai` is `>= 0.21.2, < 1.0`. Recording Studio stays `~> 6.0, >= 6.1.0`. The dummy pins GitHub tag `v0.21.2`. That release loads a root recording id before `attribution_validator` runs, and it ships no migration. This gem no longer replaces the default validator. A host validator still runs after the recording is loaded.

### Upgrade notes
- Run `bin/rails generate recording_studio_agents:migrations` again, then `bin/rails db:migrate`. That adds `recording_studio_agents_chat_tool_audits`, including `provider_turn_id`, `round_number`, and a unique index on `(provider_turn_id, call_id)`. There is no separate index on `provider_turn_id` alone. Recording Studio Logs registers it as an unpartitioned indefinite log with no summary. Do not schedule a Logs partition job for it. A database that already ran an earlier copy of that create migration does not pick up the index change from `db:migrate`. Add the unique index if it is missing, drop `index_rs_agents_chat_tool_audits_on_turn` if that single-column index is still there, or reload the schema. The turn lock is PostgreSQL only. Existing chats keep the instructions they already stored. A new chat prepends the safety preamble. `config.mcp_tools` is still `:write` unless the host changes it. `config.mcp_max_writes_per_turn` defaults to 3 and counts writes already stored for that provider turn. The count and the pending insert share a lock for that turn. `config.mcp_tool_allow` and `config.mcp_tool_deny` default to nil, which adds no name filter. An empty allow list blocks every tool.
- `recording_studio_ai` is `>= 0.21.2, < 1.0`. The dummy pins GitHub tag `v0.21.2`. 0.21.2 ships no migration. Hosts that have not yet applied 0.21.1 still copy `RefreshRecordingStudioAITerminalGuards` (`20261112120000`) and run `bin/rails db:migrate`, so the terminal guards match the columns after `correlation_id` is dropped. This gem does not ship that migration. 0.21.2 loads the root recording id `Agents.stream` rebuilds before the attribution validator runs. This gem does not replace that validator. A host validator is kept and runs after the recording is loaded.
- In-process tool writes record the signed-in person as `event.actor` when the host API is 0.20 or later. The dummy pins API `v0.22.1`. The grant does not mint an API client. `authorized_by` stays that person. Hosts on an older API still store `authorized_by` and leave the event actor empty. Boot logs a warning when `config.mcp_tools` is `:write` and the installed API is older than 0.21.2. It does not raise. On API 0.21.2, a create with no API client is stored as `actor:<Type>:<id>`, and a grant with neither a client nor an actor raises `AuthorizationError`. MCP 0.33.1 writes a usage log that needs the Logs aggregation-runs table. Install Logs, then Recording Studio AI, before migrating.
- Hosts that already load Recording Studio MCP start sending workspace tools on new chats. Set `config.mcp_tools = :off` to keep the previous chat, or `:read` to allow reads only. Writes run as the signed-in person.
- Hosts that need to force a provider on a new chat add that name to Recording Studio AI `config.allowed_provider_overrides`. Leaving the list empty keeps the profile's model.
- If `authorization_handler` is not set, use `RecordingStudioAI::AccessibleAuthorization`. It maps `recording_studio_ai.execute` to `:edit` on the workspace through Accessible. Do not set a handler that allows every signed-in person.
- Install Logs run tables (if the host does not already have them) and the Recording Studio AI migrations, in this order: `bin/rails generate recording_studio_logs:migrations`, then `bin/rails recording_studio_ai:install:migrations`, then `bin/rails db:migrate`. A new chat writes `recording_studio_ai_runs` before it calls the provider. This gem depends on `recording_studio_ai` and does not create that table. The dummy uses the same order.
- Call `recording_studio_agents_launcher` from the host layout. It needs FlatPack `>= 0.1.354`. It opens the popup through `RecordingStudioAgents::Engine.routes`, so the path follows the host mount, and it does not change the host session cookie. A later opt-in for cross-site framing would be owned by the host's session config. Sign in uses `target: "_top"`. The launcher sandbox includes `allow-top-navigation-by-user-activation`. Set `config.launcher = false` to render nothing. Pass `label:`, `title:`, or `position:` to change the defaults (`"Open chat"`, `"Chat"`, `:bottom_left`).
- Run the install generator again, or copy `request_actor` and `request_root` from the initializer template. ChatKit and the popup stay empty until both are set.
- Add staging and production origins with `config.chatkit_allowed_origins` or `CHATKIT_ALLOWED_ORIGINS`, and register those origins on the OpenAI domain allowlist. Leave the list unset outside development and the popup only allows `'self'` to frame it.
- Set `config.sign_in_path` when the host sign-in path is not Devise's `new_user_session_path`.
- Set `config.popup_stylesheet` when the host Tailwind asset is not named `tailwind`.
- Set `config.popup_theme` when the popup should use a Flatpack theme other than `rounded`. The launcher keeps its place across Turbo Drive visits. Call it once from the layout. On the Recording Studio default layout, override `app/views/layouts/recording_studio/default_layout.html.erb` and render `recording_studio_agents_launcher` after `yield`.
## [0.10.1] - 2026-11-13

### Changed
- Allow Recording Studio AI `>= 0.19.0, < 1.0` instead of `~> 0.19.0` (which rejected `0.20.0` and later). Allow Recording Studio `~> 6.0` together with the existing `>= 6.1.0` floor, so 6.1 through the last 6.x release install and 7.0 does not. Dummy GitHub pins stay Recording Studio `v6.1.0` and AI `v0.19.1`.

### Host upgrade notes
- No API or migration change. Hosts can move to any Recording Studio AI release from `0.19.0` up to, but not including, `1.0`, and any Recording Studio release from `6.1.0` up to, but not including, `7.0`.

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
