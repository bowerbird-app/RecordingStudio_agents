# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-10-21

### Added
- Opt-in per-page chats. `recording_studio_agents_chatkit(page_recording:)` sends `page_recording_id`. The server checks that the recording is inside the current workspace and that the actor can view it, then parents new chats there and limits `threads.list` to that parent. Omit it and ChatKit stays workspace-wide.
- MCP `agent_chats_list` and `agent_chats_create` take an optional `parent`. The same workspace and view checks apply. Omit it and both tools stay workspace-wide.
- `chatkit_options:` on the helper, merged over `config.chatkit_options` (a hash or a lambda of controller and purpose). The frame deep-merges that object into `setOptions` and always sets `api` itself. The hash can carry `startScreen`, `theme`, `header`, `composer`, `history`, and `initialThread`. Host options are a JSON object literal, with the same `raw json_escape` as `endpoint` and `domainKey`, so a quote in a prompt stays a quote.
- The dummy app has a workspace chat at `/agent-chat` and a Press kit page chat at `/agent-chat/page`. `Page` includes the agents capability so a page can own a chat. `PressKitPageChat` is the one declaration for that page's scope and start screen.

### Upgrade notes
- No migration.
- Include `RecordingStudio::Capabilities::Agents` on each type that should own a chat. A type without it still cannot parent one.
- Hosts that want a page-scoped embed pass that page's recording as `page_recording:`. The client id is checked again on the server.
- Set `config.chatkit_options` or pass `chatkit_options:` for a start screen, theme, header, composer placeholder, or history. Per-call options override the config. Do not put an `api` key in those options; the gem's endpoint wins.
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
