# RecordingStudioAgents

Hosted agent chats for Recording Studio. A chat is a `Session` recordable owned by a root that opted into the `:agents` capability. Turns stay in Recording Studio AI. This gem stores the session binding, a local item projection, and the retention clock.

ChatKit talks to this gem. The browser embed uses the host session. MCP uses an Oauth bearer token.

## Requirements

- Ruby 3.3 or newer
- Rails 8.1 (this repository locks `8.1.4.1`)
- Recording Studio `>= 6.1.0` (dummy GitHub tag `v6.1.0`)
- Recording Studio AI `~> 0.21.1` (dummy GitHub tag `v0.21.1`)
- Recording Studio Metrics dummy GitHub tag `v0.7.0`
- Accessible dummy GitHub tag `v0.20.0`
- Trashable dummy GitHub tag `v0.11.3`
- Root Switchable dummy GitHub tag `v0.9.7`
- Cache dummy GitHub tag `v0.5.1`
- FlatPack `>= 0.1.354` (root and dummy GitHub tag `v0.1.354`)
- view_component `>= 4.14`, `< 5` (this repository locks `4.19.0`)
- Recording Studio Users dummy GitHub tag `v0.25.2`
- Oauth dummy GitHub tag `v0.21.5`
- Recording Studio MCP dummy GitHub tag `v0.31.0`
- Recording Studio API dummy GitHub tag `v0.21.2`
- Moveable dummy GitHub tag `v4.1.0` and Icons dummy GitHub tag `v0.2.0` (API dependencies)
- Recording Studio Logs dummy GitHub tag `v0.7.1`
- Recording Studio Admin dummy GitHub tag `v2.3.3`
- Site Settings dummy GitHub tag `v0.5.1`

This gem does not depend on MCP, API, or Oauth. The dummy pins API `v0.21.2`, MCP `v0.31.0`, and Oauth `v0.21.5`. API 0.20 records the access-grant actor on a resource update. An in-process chat write uses the signed-in person as that actor. `agent_chats_create` still records the OAuth client, because this gem chooses that actor. An older API leaves the in-process event actor empty. API 0.21.2 keys a create with no API client as `actor:<Type>:<id>`. A grant with neither a client nor an actor raises `AuthorizationError`.

The provider API key stays in Recording Studio AI. This gem does not read one.

## Host setup

```ruby
gem "recording_studio_agents", github: "bowerbird-app/RecordingStudio_agents"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.354"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.1.0"
gem "recording_studio_ai", github: "bowerbird-app/RecordingStudio_AI", tag: "v0.21.1"
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.7.1"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.7.0"
gem "view_component", "4.19.0"
```

Metrics `v0.7.0` and Logs `v0.7.1` allow Recording Studio `>= 6.1.0`. AI 0.21.1 does too. Several other dummy pins still declare `recording_studio` below 5, including Trashable `v0.11.3`, Users `v0.25.2`, Root Switchable `v0.9.7`, Attachable `v0.20.2`, API, Oauth, MCP, Site Settings, and Cache. Both Gemfiles load `test/support/widen_recording_studio_requirement.rb` before Bundler reads gemspecs. That file rewrites a `recording_studio` requirement that rejects 6.1.0 into `>= 6.1.0`. It is not part of the installed gem. A host Gemfile that includes one of those older gems has to widen the requirement the same way.

Register the recordable, opt a parent type into `:agents`, and copy migrations:

```ruby
RecordingStudio.configure do |config|
  config.recordable_types += ["RecordingStudioAgents::Session"]
end

RecordingStudioAgents.configure do |config|
  config.layout = nil
end
```

`config.layout` accepts `nil`, `false`, a layout name, or a callable invoked as `call(controller:)`. `nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`. `false` renders with no layout. A positional parameter raises `ArgumentError`. See `docs/layout.md`.

## Required configuration

ChatKit and the popup need the signed-in person and the current workspace. The install generator writes both into `config/initializers/recording_studio_agents.rb`. `request_actor` uses `current_user` when the controller responds to it, and the host session otherwise, then sets `Current.actor` when `Current` responds to `actor=`. `request_root` asks Root Switchable for that person's current root. Leave either one as the empty default and a signed-in visitor looks signed out, or a person with a workspace sees the empty state.

```ruby
config.request_actor = lambda do |controller|
  user = controller.send(:current_user) if controller.respond_to?(:current_user, true)
  user ||= controller.request.env["warden"]&.user(:user) if controller.respond_to?(:request)
  Current.actor = user if defined?(Current) && Current.respond_to?(:actor=)
  user
end

config.request_root = lambda do |controller|
  actor = defined?(Current) ? Current.actor : nil
  actor = controller.send(:current_user) if actor.blank? && controller.respond_to?(:current_user, true)
  actor ||= controller.request.env["warden"]&.user(:user) if controller.respond_to?(:request)
  next if actor.blank?
  next unless defined?(RecordingStudio::RootSwitchable)

  device_key = RecordingStudio::RootSwitchable::DeviceKey.fetch(controller: controller)
  RecordingStudio::RootSwitchable.resolve_current_root(
    controller: controller,
    actor: actor,
    device_key: device_key
  ).root_recording
rescue RecordingStudio::RootSwitchable::DeviceKey::Unavailable
  nil
end
```

```ruby
class Workspace < ApplicationRecord
  include RecordingStudio::Capabilities::Agents.to
end
```

```bash
bin/rails generate recording_studio_agents:migrations
bin/rails generate recording_studio_logs:migrations
bin/rails recording_studio_ai:install:migrations
bin/rails db:migrate
```

Install Logs run tables (if the host does not already have them) and the Recording Studio AI migrations, in that order, before `db:migrate`. A new chat writes a Recording Studio AI run before it calls the provider. `recording_studio_ai` is a runtime dependency, and those tables are not created by this gem. The dummy installs Logs, then Recording Studio AI, in that same order. AI 0.21.1 ships `RefreshRecordingStudioAITerminalGuards` (`20261112120000`) so `rsai_terminal_runs_guard` and `rsai_terminal_batches_guard` match the columns after `correlation_id` is dropped. Re-run `bin/rails recording_studio_ai:install:migrations` on a host that already copied the 0.20.0 migrations, then `bin/rails db:migrate`.

Schedule `RecordingStudioAgents::ExpireSessionsJob`. It closes chats whose `expires_at` has passed. Closing deletes the provider session through Recording Studio AI first. An already-gone provider session is success, and the local chat, items, and binding are removed. A different provider failure leaves the local rows in place for a later retry.

## Services

- `RecordingStudioAgents::Sessions::Create` opens a provider session, then records the chat under the parent.
- `RecordingStudioAgents::Sessions::Append` sends another user message and refreshes the retention clock.
- `RecordingStudioAgents::Sessions::Rename` revises the chat title. The previous snapshot stays.
- `RecordingStudioAgents::Sessions::Close` deletes the provider session, then purges the local chat.
- `RecordingStudioAgents::Sessions::Expire` closes every expired binding. One failure does not stop the rest. Expiry is system cleanup scoped to the recording and its root. It does not use the creator and does not check access. A user `Close` still requires edit access on the chat.

A chat stores the instructions it was opened with. A gem-owned safety preamble comes first. The host default is `config.instructions`, after that preamble. A per-chat override is appended after that default, with a blank line between them, and never replaces the preamble or the host default. `config.instructions_override` defaults to `:none`, so a real override is rejected and the chat is not created. A host opts in with `:admin` (Recording Studio Accessible admin on the workspace) or `:edit`. Blank or whitespace-only text uses the host default. The override must be a string no longer than `config.max_instructions_length` (4000). ChatKit `threads.create` does not accept `instructions`; a client that sends the field gets a 400. MCP `agent_chats_create` and host Ruby (`Sessions::Create`) can pass it when the config allows it. The stored copy is personal data. The engine adds an exact `instructions` filter to `filter_parameters`, and the chat record filters its own `instructions` attribute, so request logs and `inspect` do not show it. A host parameter such as `shipping_instructions` is not filtered. The 30-day cleanup deletes those stored instructions with the chat.

Create and append are idempotent on their keys inside one root. The same create key in a different root opens a second chat. The binding stores `root_recording_id`, and the unique index is `(root_recording_id, create_idempotency_key)`. Item keys use the same pair. A repeated key inside one root still returns the existing chat or message. That replay does not check a new parent and does not check or store a new instructions override. Two creates that overlap on that key do the same: the loser drops the extra provider session and returns the chat that won.

## ChatKit

`POST /recording_studio_agents/chatkit` accepts the ChatKit protocol and answers with JSON or server-sent events. The host session resolves the actor. The root is the workspace selected in Root Switchable (`RecordingStudio::RootSwitchable.resolve_current_root`), not the oldest workspace. Client metadata ids are ignored. Create, append, rename, and delete go through the Sessions services. Streaming, cancel, and reading a finished first turn go through `RecordingStudioAI::Agents`. A chat the actor cannot view is a 404, the same as a missing chat.

`threads.create` is not streamed by Recording Studio AI. After the session is saved, the endpoint reads the provider stream, and reads saved items when that stream has no text. `text_delta` events become ChatKit text deltas. An unsupported operation returns a protocol error.

`recording_studio_agents_chatkit` renders the official `<openai-chatkit>` web component from `https://cdn.platform.openai.com/deployments/chatkit/chatkit.js`. Its custom backend is this endpoint. The component's `fetch` sends the session cookie and the CSRF token. `domainKey` comes from `config.chatkit_domain_key`. The setup script is the asset `recording_studio_agents/chatkit.js`, served from the host. Per-render values (`endpoint`, `domainKey`, and `hostOptions`) are HTML data attributes. The script reads those attributes, so a quote in any of them stays a quote. The browser does not receive an OpenAI API key, a client secret, or an Agent Builder workflow. The panel sits in a FlatPack card. Its height is the Tailwind class `h-[min(40rem,calc(100dvh-16rem))]`, so the host Tailwind build has to scan this gem's views. An inner wrapper uses the card radius and `overflow-hidden` so the ChatKit iframe follows the rounded corners.

Pass `page_recording:` with the page's recording to scope that embed to the page. The helper adds `page_recording_id` to the endpoint. The server loads that recording again, checks it sits inside the current workspace, and checks the actor can view it. A missing or cross-workspace id is a 404. An id inside the workspace that the actor cannot view is a 403. With a valid id, new chats use that recording as their parent and `threads.list` returns only those chats. Leave it off and the endpoint behaves as before: new chats belong to the workspace and the list includes every chat in it. The same checks apply to MCP `parent` on `agent_chats_list` and `agent_chats_create`. Omit `parent` and those tools keep the workspace behavior. A parent can own a chat only when its type includes the agents capability:

```ruby
include RecordingStudio::Capabilities::Agents.to
```

The dummy `Page` model uses that line. A folder still cannot. A trashed page is treated as missing. A present id that is not a string, such as `page_recording_id[]`, is a 404. An id whose type cannot hold a chat is a 422.

`chatkit_options:` is merged over `config.chatkit_options` and sent to `setOptions`. The config value is a hash, or a lambda of 0, 1, or 2 arguments. Zero arguments are called with none. One argument receives the controller. Two arguments receive the controller and `config.purpose`. The lambda is not called when the setup notice is showing. Use the ChatKit keys you need: `startScreen` (greeting and prompts with `label`, `prompt`, and optional `icon`), `theme`, `header`, `composer` (`placeholder`), `history`, and `initialThread`. `setOptions` replaces the previous options, so the frame always sets `api` itself. A host `api` key is dropped. `initialThread: nil` keeps the new-thread start screen. One host declaration can pass the same page into `page_recording:` and the start screen into `chatkit_options:`. The dummy page at `/agent-chat/page` does that for the Press kit page. `/agent-chat` stays the workspace chat.

A new chat sends `config.provider` only when Recording Studio AI lists that name in `allowed_provider_overrides`. The default is `openai`, which ChatKit readiness uses. It is not sent as an override, so the profile picks the model. Add the name to `allowed_provider_overrides` when a host must force that provider.

When Recording Studio MCP and Recording Studio API are both loaded, a new chat also sends that person's workspace tools as function tools. The list is built from their Accessible grant on the current root. Reads and writes are both included. `config.mcp_tools` is `:write` by default, `:read` for read-only tools, or `:off` to send none. The tools this gem registers (`agent_chats_list`, `agent_chats_create`, `agent_chats_read`, `agent_chats_append`, `agent_items_list`, and `agent_items_read`) are left out, so a tool call cannot open another chat turn. Each call runs in this process through `RecordingStudioMcp::Dispatcher` as the person who is signed in for this request, then the result is posted back to the hosted session. The Accessible check uses that person's grant. A generic update stores that person as the event actor and as `authorized_by`. The grant does not set an API client, so the event has no impersonator. API 0.20 writes the access-grant actor onto that event. An older API leaves the actor empty and still stores `authorized_by` when it supports that stamp. API 0.21.2 stores an in-process create, which has no API client, under `actor:<Type>:<id>`. The chat still sends `idempotency_key: call_id`. A grant with neither a client nor an actor raises `AuthorizationError`. At boot, when `config.mcp_tools` is `:write` and the installed `recording_studio_api` is older than 0.21.2, this gem logs a warning that in-process creates need 0.21.2 and that the host should upgrade. It does not raise. Set `config.mcp_tools` to `:read` or `:off` to skip that warning. A call the grant does not allow comes back as an error result. The tool output is not raised out of the turn. The same call is counted in the MCP usage log, and it uses the API read or write rate limit. `ChatToolLimit` copies API's private rate-limit key layout (`namespace:api_read|api_write:identifier:window`, default namespace `recording_studio_api`) and its increment script. Replace it with a public API limiter when one exists. While API access is disabled, the call returns an error and does not run. A host without MCP sends no tools, and the chat behaves as before. Tool definitions are fixed when the chat is created. Turning tools off, or down to read-only, still applies to calls on a chat that was opened earlier. A dropped model stream that is still waiting on tool calls is answered from the recovered calls. If posting those results times out, the pending calls are read again before a retry, because the first post may still be in flight. One provider turn answers at most 8 rounds of tool calls. A resumed, recovered, or retried stream counts rounds already recorded for that turn id, then refuses the next call. If the run is still waiting, it is cancelled and the chat shows a failure. `config.mcp_max_writes_per_turn` (default 3) counts write calls for that same turn id, including writes already recorded. `config.mcp_tool_allow` and `config.mcp_tool_deny` limit which calls run. An empty allow list blocks every tool. See [Security](#security). `config.mcp_tools` stays `:write` unless the host sets it.

The component renders when the ChatKit domain key is set and the configured provider has a hosted-agent model and its credential. The default provider is OpenAI, which needs `config.openai_api_key` or `config.openai_client`. A provider with no hosted-agent model, such as Gemini on the current Recording Studio AI release, shows a setup notice instead of asking for an invented key. The self-hosted ChatKit server is unchanged.

Set the OpenAI API key through Recording Studio AI, in `config/initializers/recording_studio_ai.rb`:

```ruby
config.openai_api_key =
  Rails.application.credentials.dig(:openai, :api_key) || ENV.fetch("OPENAI_API_KEY", nil)
```

Register the page's origin, including scheme and port, in the [OpenAI domain allowlist](https://platform.openai.com/settings/organization/security/domain-allowlist). Assign that domain key in `config/initializers/recording_studio_agents.rb`:

```ruby
config.chatkit_domain_key = ENV.fetch("CHATKIT_DOMAIN_KEY", nil)
```

The dummy page at `/agent-chat` uses the same helper. With neither key set, it shows the setup notice and does not call OpenAI.

## Popup

`recording_studio_agents_launcher` puts a FlatPack `FloatingFrame` on the host layout. It opens the popup through `RecordingStudioAgents::Engine.routes`, so the path follows the host mount (`GET /recording_studio_agents/popup` at the default mount). It is a same-site iframe. FlatPack `0.1.354` or newer supplies that component. The root Gemfile and the dummy pin tag `v0.1.354`.

```erb
<%= recording_studio_agents_launcher %>
```

The launcher sits at the bottom left. The framed page has no padding, so the chat meets the panel edges. The iframe sandbox is `allow-scripts allow-same-origin allow-forms allow-popups allow-top-navigation-by-user-activation`, and `allow` is `clipboard-write`. Sign in uses `target: "_top"`. That sandbox token lets the click leave the frame.

```erb
<%= recording_studio_agents_launcher(label: "Ask", title: "Studio chat", position: :bottom_right) %>
```

`label` names the launcher. `title` is the panel heading and the iframe name. `position` is `:bottom_left` (the default), `:bottom_right`, `:top_left`, or `:top_right`.

`config.launcher` defaults to on and must be `true` or `false`. Set it to `false` and the helper renders nothing.

```ruby
config.launcher = false
```

The popup and the host page have to be on the same site. The helper does not read or change the session cookie. The page renders `recording_studio_agents_chatkit` in a bare layout that fills the frame. It does not take a page. The chat uses the workspace from `config.request_root` (Root Switchable's current root). A signed-in person with no workspace sees an empty state instead of the chat.

The bare layout loads `config.popup_stylesheet`, which defaults to the host `tailwind` stylesheet. Set it to another asset name, or to `nil` to skip the tag. FlatPack's empty state and the chat height are utility classes, and this document does not inherit the host page's CSS.

Pass `fill: true` to the helper when a host screen should use the same full-height chat. The popup does that. Other screens keep the card height.

### Framing and content security policy

The popup supports same-site framing only. The host page and the popup have to be on the same site, so the browser sends the host session cookie with the framed request and with `POST /chatkit`. Cross-site framing is not supported. A later opt-in for that would belong to the host's session config, not to this gem. The popup does not change the session cookie. `POST /chatkit` uses the host session and Rails `protect_from_forgery`.

Only the popup action sets a content security policy. The rest of the app keeps its own policy. The popup allows the ChatKit script (`https://cdn.platform.openai.com`), the setup asset from `'self'`, connections to that host and `https://api.openai.com`, and a frame from the ChatKit host. `script-src` does not include `'unsafe-inline'`. The setup script is not inline, so it does not need a CSP nonce. When `asset_host` makes that script absolute (a string, a proc, or an `assets%d` host), its origin is added to `script-src`, so the CDN copy is allowed. A relative script stays covered by `'self'`. `frame-ancestors` is `'self'` plus `config.chatkit_allowed_origins`. The action drops `X-Frame-Options` so those origins can frame the page.

Development and test default to `http://localhost:3000` and `http://127.0.0.1:3000`. Every other environment starts from an empty list, so a missing setting fails safe to `'self'`. Set staging and production in the initializer, or with `CHATKIT_ALLOWED_ORIGINS` (comma-separated). Values are normalized the same way Embeddable reads an origin: scheme, host, and a non-default port. A path is dropped.

```ruby
config.chatkit_allowed_origins = ENV["CHATKIT_ALLOWED_ORIGINS"] if ENV["CHATKIT_ALLOWED_ORIGINS"].present?
config.chatkit_domain_key = ENV["CHATKIT_DOMAIN_KEY"].presence
```

Register those same origins in the [OpenAI domain allowlist](https://platform.openai.com/settings/organization/security/domain-allowlist) and put the domain key in `CHATKIT_DOMAIN_KEY`. Those origins are who may frame the popup. They do not make a cross-site session cookie.

### Who can run an agent

If no `authorization_handler` is set, use Recording Studio AI's `AccessibleAuthorization`. It maps `recording_studio_ai.execute` to `:edit` on the workspace through Accessible. Do not set a handler that allows every signed-in person. In `config/initializers/recording_studio_ai.rb`:

```ruby
config.authorization_handler = RecordingStudioAI::AccessibleAuthorization.method(:call)
```

The dummy app sets this. It needs the `recording-studio-accessible` gem, which Recording Studio AI's handler already calls.

Recording Studio AI 0.21.1's default `attribution_validator` accepts only a `Recording`. `Agents.stream` rebuilds the stored root as an object with an id, and that default then rejects the turn. This gem replaces that default: the id is loaded, and it must be a root recording whose parent is empty and whose `root_recording_id` is its own id. A context recording must belong to that root. Assign `config.attribution_validator` in `config/initializers/recording_studio_ai.rb` for a stricter check. This gem leaves a host-assigned validator in place.

A signed-out visitor sees a sign-in prompt instead of the chat. The button uses `config.sign_in_path`. When that is unset, the path is `main_app.new_user_session_path` if the route exists, and `/users/sign_in` otherwise. A string is a path. A lambda receives the controller:

```ruby
config.sign_in_path = "/login"
config.sign_in_path = ->(controller) { controller.main_app.new_user_session_path }
```

`POST /recording_studio_agents/chatkit` with no actor returns 401. A signed-in actor who is not allowed to execute returns 403.

The sign-in copy is in `config/locales/en.yml` and `config/locales/fr.yml`.

## Security

In-process chat tools treat tool results as data. This limits what one reply can do. It does not make the model obey.

What this does:

- Every chat starts with a gem-owned preamble, before `config.instructions` and before any per-session override. It says tool output is untrusted data, never instructions, and to make no write unless the user asked for it in this turn. There is no setting that removes it. Host text and an override are appended after it.
- A successful tool result is posted back as JSON, `{"untrusted_tool_output":"<text>"}`. That string still stops at 256 KB. A tool error that is not one of this gem's own refusal sentences is wrapped the same way. Refusals such as `tool is not allowed` and `write limit reached` stay plain text so the model can read them.
- `config.mcp_max_writes_per_turn` defaults to 3 and must be a positive integer. It counts write-tool calls for one provider turn, across every round, including a resumed, recovered, or retried stream. The count is the audit rows already stored for that turn id. Read versus write uses Recording Studio MCP `ToolSurface#read_only_tool?`. A later write in that turn is answered with `write limit reached`. The turn continues, and reads are still answered. The 8-round cap uses the same turn id. `config.mcp_tools` stays `:write` by default. `:read` and `:off` are unchanged.
- `config.mcp_tool_allow` and `config.mcp_tool_deny` are arrays of tool names, or nil. They apply when the function list is built and again when a call runs. Deny wins. When allow is set, only those names are listed or called. Nil means no extra name filter. An empty allow list blocks every tool: none are listed, and every call is refused.
- Each chat tool call writes one row to `recording_studio_agents_chat_tool_audits` before the tool runs, with outcome `pending`, then updates that outcome. A crash mid-call leaves `pending`. Recording Studio Logs registers that table (`retention: :indefinite`, no partition, no summary). The row stores the actor type and id, the chat recording id, the provider turn id, the round number, the tool name, `read` or `write`, up to 50 argument keys, the outcome (`pending`, `ok`, `error`, `refused`, or `limited`), and the call id. A key is kept only when it is identifier-like and at most 64 characters; a longer identifier is truncated to 64, and anything else is dropped. It does not store argument values.

What this does not do:

- It does not stop a model from ignoring the preamble.
- It does not ask the person to approve a write.
- It does not read MCP tool annotations.
- It does not rewrite the words inside a tool result, beyond the envelope and the size cap.
- It does not cover MCP calls made outside this chat, including `agent_chats_*` and `agent_items_*`.

## Dummy app

The dummy app validates the engine in a host with Recording Studio Users, Oauth, MCP, FlatPack, and Recording Studio's default layout. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. ChatKit keeps that session. MCP at `/recording_studio_mcp` uses an Oauth bearer token.

The dummy also has press kits at `/press_kits`. A kit is a recordable with the agents capability, so a chat can be scoped to it, and Attachable dummy GitHub tag `v0.20.2` stores its photos. That pin lives in the dummy Gemfile only. It is not a gemspec dependency. MCP `list`, `show`, and `update` on type `PressKit` read and edit kits in the granted workspace. A successful generic `update` stores the access-grant actor. In the dummy that is the OAuth authorization, and the OAuth client is the impersonator. `agent_chats_create` stores the OAuth client as the event actor. Both store the approving person in `authorized_by_type` and `authorized_by_id`. A client that sends `authorized_by_type`, `authorized_by_id`, or `metadata` on `update` is refused, because those are not writable fields. The same arguments on `agent_chats_create` are dropped, and the stored event keeps the server stamp.

## MCP

The gem registers the chat tools when the host has loaded Recording Studio API, and the `agent-chats` skill when the host has loaded Recording Studio MCP. Each tool's `openapi` hash includes a success JSON schema and example so MCP docs can show sample output. The host mounts MCP, API, and Oauth and draws the protected-resource metadata. A bearer token acts in the workspace on its access grant. The browser switcher and a session cookie on the same request do not change that grant. Reads call `access_grant.authorize!` with `:view`. Writes call it with `:edit`. The catalog still uses the grant's `OauthAuthorization` for visibility. `agent_chats_create` records the OAuth client as the event actor and the approving person in `authorized_by_type` and `authorized_by_id` when the host API provides that stamp. Client-sent copies of those keys, and a client metadata bag, are not stored. The provider attribution for the chat stays the grant actor. The generic `update` tool records the access-grant actor and the same stamp. On API 0.20 the OAuth client is the impersonator when it is a different record from that actor. It refuses a client `authorized_by_*` or `metadata` argument as an unknown field.

| Tool | What it does |
| --- | --- |
| `agent_chats_list` | Chats in the granted workspace. Optional `parent` limits the list to that parent |
| `agent_chats_create` | Opens a chat. Requires `input` and `idempotency_key`. Optional `parent` chooses the parent. A repeated key returns the existing chat and ignores `parent` |
| `agent_chats_read` | One chat |
| `agent_chats_append` | Adds a user message |
| `agent_items_list` | Items on one chat |
| `agent_items_read` | One item |

`skill://agent-chats/SKILL.md` is the MCP resource for those tools.
