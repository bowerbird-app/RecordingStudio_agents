# RecordingStudioAgents

Hosted agent chats for Recording Studio. A chat is a `Session` recordable owned by a root that opted into the `:agents` capability. Turns stay in Recording Studio AI. This gem stores the session binding, a local item projection, and the retention clock.

ChatKit talks to this gem. The browser embed uses the host session. MCP uses an Oauth bearer token.

## Requirements

- Recording Studio Agents `0.21.0`
- Ruby 3.3 or newer
- Rails 8.1 (this repository locks `8.1.4.1`)
- Recording Studio gemspec `~> 7.7`. This repository pins `~> 7.8` (tag `v7.8.0`). Hosts MUST run the Recording Studio 7.4, 7.5, and 7.7 migrations. The dummy does not vendor those migrations.
- Recording Studio AI gemspec `~> 0.25`. This repository pins `~> 0.26` (tag `v0.26.0`)
- Recording Studio Metrics dummy GitHub tag `v0.10.0`
- Accessible dummy GitHub tag `v0.58.0`
- Trashable dummy GitHub tag `v1.3.0`
- Root Switchable dummy GitHub tag `v0.17.0`
- Cache dummy GitHub tag `v0.8.0`
- FlatPack gemspec `>= 0.1.354` (root GitHub tag `v0.2.0`; dummy GitHub tag `v0.2.0`). Hosts moving to 0.2 remove the manual `flat_pack/heroicons` importmap pin and any `flat-pack--icon` controller registration.
- view_component `>= 4.14`, `< 5` (this repository locks `~> 4.19`)
- Recording Studio Users dummy GitHub tag `v0.37.0`
- Oauth dummy GitHub tag `v0.25.1`
- Recording Studio MCP dummy GitHub tag `v0.45.2` (`~> 0.45.2`)
- Recording Studio API dummy GitHub tag `v1.21.3`
- Moveable dummy GitHub tag `v6.1.0` and Icons dummy GitHub tag `v0.5.0` (API dependencies)
- Recording Studio Logs dummy GitHub tag `v0.9.0`
- Recording Studio Admin dummy GitHub tag `v2.20.0`
- Site Settings dummy GitHub tag `v0.6.0`
- Attachable dummy GitHub tag `v0.34.0`

This gem depends on Recording Studio API `>= 0.26.0, < 2.0`. It does not depend on MCP or Oauth. The dummy pins API `v1.21.3`, MCP `v0.45.2`, and Oauth `v0.25.1`. MCP `0.45.2` requires API `>= 1.21.3`. API `1.19.0` needs Recording Studio `>= 7.7`, which the `~> 7.8` pin satisfies. Chat `:id` endpoints register `recordable_type: "RecordingStudioAgents::Session"`. API 0.20 records the access-grant actor on a resource update. An in-process chat write uses the signed-in person as that actor. `create_agent_chat` still records the OAuth client, because this gem chooses that actor. An older API leaves the in-process event actor empty. API 0.21.2 keys a create with no API client as `actor:<Type>:<id>`. A grant with neither a client nor an actor raises `AuthorizationError`. Recording Studio refuses `record!` unless the host sets `config.authorize_write`. The dummy authorizer allows a write when an actor is present. `root_recording_for` only finds a root. Create one with `create_root_recording!(recordable, actor:)`. Trashable 0.17 removed `kept_sql`. Use `Recording.kept`. Root Switchable still requires an Accessible `:view` grant on the current root before the mounted switch page renders.

The provider API key stays in Recording Studio AI. This gem does not read one.

## Host setup

```ruby
gem "recording_studio_agents", github: "bowerbird-app/RecordingStudio_agents"
gem "flat_pack", "~> 0.2", github: "bowerbird-app/flatpack", tag: "v0.2.0"
gem "recording_studio", "~> 7.8", github: "bowerbird-app/RecordingStudio", tag: "v7.8.0"
gem "recording_studio_ai", "~> 0.26", github: "bowerbird-app/RecordingStudio_AI", tag: "v0.26.0"
gem "recording_studio_api", "~> 1.21", github: "bowerbird-app/RecordingStudio_api", tag: "v1.21.3"
gem "recording_studio_logs", "~> 0.9", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.9.0"
gem "recording_studio_metrics", "~> 0.10", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.10.0"
gem "view_component", "~> 4.19"
```

Cache `v0.8.0`, Attachable `v0.34.0`, Site Settings `v0.6.0`, and Icons `v0.5.0` are pinned in the dummy Gemfile. Attachable `v0.34.0` accepts API `>= 1.1.0, < 2.0` and FlatPack `>= 0.1.376`. There is no Bundler gemspec rewrite.

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

### Site switch

`config.enabled` defaults to `true`, so an upgrade changes nothing. Set it to `false` to turn agent chats off for the whole site. There is no per-workspace switch and no new table.

While it is off:

- `recording_studio_agents_launcher` and `recording_studio_agents_chatkit` render nothing. `config.launcher = true` does not bring the launcher back.
- Every engine route responds 404. That includes `POST /recording_studio_agents/chatkit` with no CSRF token, which is 404 and not 422 or 401.
- `Sessions::Create` and `Sessions::Append` raise `RecordingStudioAgents::DisabledError` before they call the provider. They write no chat, item, or binding rows.
- `list_agent_chats`, `create_agent_chat`, `read_agent_chat`, `append_agent_chat`, `list_agent_items`, and `read_agent_item` return not found.
- `ExpireSessionsJob` still closes expired chats. A reply already in progress is not stopped.

`true` and `false` are the usual values. A lambda is called on every check, with the controller, or with no argument. A service or an MCP tool passes `nil`. Return a false value and that check is off. A lambda that raises is off. The log line is `[recording_studio_agents] enabled` plus the error class. It leaves out the message, request bodies, and secrets.

`RecordingStudioAgents::Availability.enabled?` reads the setting each time. It does not remember the last result.

A boolean taken from the environment is fixed when the process boots. Restart after you change it.

```ruby
config.enabled = ENV.fetch("RS_AGENTS_ENABLED", "true") != "false"
```

`config/recording_studio_agents.yml` accepts a boolean:

```yaml
enabled: false
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

Install Logs run tables (if the host does not already have them) and the Recording Studio AI migrations, in that order, before `db:migrate`. A new chat writes a Recording Studio AI run before it calls the provider. `recording_studio_ai` is a runtime dependency, and those tables are not created by this gem. The dummy installs Logs, then Recording Studio AI, in that same order. AI 0.21.2 ships no migration. Hosts that have not yet applied 0.21.1 still need `RefreshRecordingStudioAITerminalGuards` (`20261112120000`) so `rsai_terminal_runs_guard` and `rsai_terminal_batches_guard` match the columns after `correlation_id` is dropped. Re-run `bin/rails recording_studio_ai:install:migrations` on a host that already copied the 0.20.0 migrations, then `bin/rails db:migrate`.

Schedule `RecordingStudioAgents::ExpireSessionsJob`. It closes chats whose `expires_at` has passed. Closing deletes the provider session through Recording Studio AI first. An already-gone provider session is success, and the local chat, items, and binding are removed. A different provider failure leaves the local rows in place for a later retry.

## Services

- `RecordingStudioAgents::Sessions::Create` opens a provider session, then records the chat under the parent.
- `RecordingStudioAgents::Sessions::Append` sends another user message and refreshes the retention clock.
- `RecordingStudioAgents::Sessions::Rename` revises the chat title. The previous snapshot stays.
- `RecordingStudioAgents::Sessions::Close` deletes the provider session, then purges the local chat.
- `RecordingStudioAgents::Sessions::Expire` closes every expired binding. One failure does not stop the rest. Expiry is system cleanup scoped to the recording and its root. It does not use the creator and does not check access. A user `Close` still requires edit access on the chat.

A chat stores the instructions it was opened with. A gem-owned safety preamble comes first. The host default is `config.instructions`, after that preamble. A per-chat override is appended after that default, with a blank line between them, and never replaces the preamble or the host default. `config.instructions_override` defaults to `:none`, so a real override is rejected and the chat is not created. A host opts in with `:admin` (Recording Studio Accessible admin on the workspace) or `:edit`. Blank or whitespace-only text uses the host default. The override must be a string no longer than `config.max_instructions_length` (4000). ChatKit `threads.create` does not accept `instructions`; a client that sends the field gets a 400. MCP `create_agent_chat` and host Ruby (`Sessions::Create`) can pass it when the config allows it. The stored copy is personal data. The engine adds an exact `instructions` filter to `filter_parameters`, and the chat record filters its own `instructions` attribute, so request logs and `inspect` do not show it. A host parameter such as `shipping_instructions` is not filtered. The 30-day cleanup deletes those stored instructions with the chat.

Create and append are idempotent on their keys inside one root. The same create key in a different root opens a second chat. The binding stores `root_recording_id`, and the unique index is `(root_recording_id, create_idempotency_key)`. Item keys use the same pair. A repeated key inside one root still returns the existing chat or message. That replay does not check a new parent and does not check or store a new instructions override. Two creates that overlap on that key do the same: the loser drops the extra provider session and returns the chat that won.

## ChatKit

`POST /recording_studio_agents/chatkit` accepts the ChatKit protocol and answers with JSON or server-sent events. The host session resolves the actor. The root is the workspace selected in Root Switchable (`RecordingStudio::RootSwitchable.resolve_current_root`), not the oldest workspace. Client metadata ids are ignored. Create, append, rename, and delete go through the Sessions services. Streaming, cancel, and reading a finished first turn go through `RecordingStudioAI::Agents`. A chat the actor cannot view is a 404, the same as a missing chat. A rescued error on that request is one Rails log line starting with `[recording_studio_agents.chatkit]`. A client disconnect is info. Any other rescued error is a warning. Invalid JSON, a rejected page, a missing thread, and a signed-out request keep their HTTP status and JSON body. The line leaves out the request body, headers, cookies, and credentials.

A hosted read can send an assistant message again after a tool round, as `message_completed` and with no text deltas. ChatKit keeps the first copy in that turn. The repeat is dropped when the provider item id and the text both match a message already shown, or when there is no item id and the text matches. Text deltas are always shown. A different item id, different text, or the same words on the next turn are shown. A dropped repeat adds no bubble, no thread event, and no stored item.

The same log prefix records phase timings. A new chat logs `create_tools`, `create_provider` (with `tools=`, a count), and `create_persist` instead of one `create` line. A reply still logs `append`. Every timing line also has `q=` (SQL statements) and `db=` (milliseconds in those statements). Schema and cached statements are left out. `model_stream` is the first provider read, until that read returns tool calls or ends. `ttft` is the time from the start of the request until the first assistant text delta is written to the client. A tool line adds `name=`. A round line adds `n=`, `answers_ms=` for the tool calls, and `model_ms=` for posting those results and reading the continuation. `total` adds `dropped=` when a replay was dropped. The clock is monotonic. The line does not include message text, tool arguments, tool results, page context, tokens, headers, or secrets.

A dropped replay logs `[recording_studio_agents.chatkit] dedupe dropped item_id=<id|none> by=<id|text>`. The line has no message text.

`threads.list` reads one page from SQL. The order is `created_at` descending, then `id` descending. `after` is that keyset. The server fetches `limit + 1` rows, checks Accessible on those rows, and keeps reading when a row is not viewable so a full page still comes back while more viewable chats exist. The limit stays capped at 50. A page embed still lists only chats parented by that page.

`threads.create` and `threads.add_user_message` write the opening events before the chat is saved and before the provider runs. A new thread sends `thread.created`, the user message, and `stream_options`. A reply sends the user message and `stream_options`. The thread id and the user item id in those events are the ids stored afterwards. The provider call is not streamed by Recording Studio AI. After the session is saved, the endpoint reads the provider stream, and reads saved items when that stream has no text. `text_delta` events become ChatKit text deltas. An unsupported operation returns a protocol error.

`recording_studio_agents_chatkit` renders the official `<openai-chatkit>` web component from `https://cdn.platform.openai.com/deployments/chatkit/chatkit.js`. Its custom backend is this endpoint. The component's `fetch` sends the session cookie and the CSRF token. `domainKey` comes from `config.chatkit_domain_key`. The setup script is the asset `recording_studio_agents/chatkit.js`, served from the host. Per-render values (`endpoint`, `domainKey`, and `hostOptions`) are HTML data attributes. The script reads those attributes, so a quote in any of them stays a quote. The browser does not receive an OpenAI API key, a client secret, or an Agent Builder workflow. The panel sits in a FlatPack card. Its height is the Tailwind class `h-[min(40rem,calc(100dvh-16rem))]`, so the host Tailwind build has to scan this gem's views. An inner wrapper uses the card radius and `overflow-hidden` so the ChatKit iframe follows the rounded corners.

Pass `page_recording:` with the page's recording to scope that embed to the page. The helper adds `page_recording_id` to the endpoint. The server loads that recording again, checks it sits inside the current workspace, and checks the actor can view it. A missing or cross-workspace id is a 404. An id inside the workspace that the actor cannot view is a 403. With a valid id, new chats use that recording as their parent and `threads.list` returns only those chats. Leave it off and the endpoint behaves as before: new chats belong to the workspace and the list includes every chat in it. The same checks apply to MCP `parent` on `list_agent_chats` and `create_agent_chat`. Omit `parent` and those tools keep the workspace behavior. A parent can own a chat only when its type includes the agents capability:

```ruby
include RecordingStudio::Capabilities::Agents.to
```

The dummy `Page` model uses that line. A folder still cannot. A trashed page is treated as missing. A present id that is not a string, such as `page_recording_id[]`, is a 404. An id whose type cannot hold a chat is a 422.

`chatkit_options:` is merged over `config.chatkit_options` and sent to `setOptions`. The config value is a hash, or a lambda of 0, 1, or 2 arguments. Zero arguments are called with none. One argument receives the controller. Two arguments receive the controller and `config.purpose`. The lambda is not called when the setup notice is showing. Use the ChatKit keys you need: `startScreen` (greeting and prompts with `label`, `prompt`, and optional `icon`), `theme`, `header`, `composer` (`placeholder`), `history`, and `initialThread`. `setOptions` replaces the previous options, so the frame always sets `api` itself. A host `api` key is dropped. `initialThread: nil` keeps the new-thread start screen. One host declaration can pass the same page into `page_recording:` and the start screen into `chatkit_options:`. The dummy page at `/agent-chat/page` does that for the Press kit page. `/agent-chat` stays the workspace chat.

A new chat sends `config.provider` only when Recording Studio AI lists that name in `allowed_provider_overrides`. The default is `openai`, which ChatKit readiness uses. It is not sent as an override, so the profile picks the model. Add the name to `allowed_provider_overrides` when a host must force that provider.

When Recording Studio MCP and Recording Studio API are both loaded, a new chat also sends that person's workspace tools as function tools. The list is built once for that turn from their Accessible grant on the current root, and the same grant and tool surface are reused for the write cap, the audit kind, and each call in the turn. The grant does not authorize a write by itself. The call still goes through Recording Studio and Accessible when it runs, so a grant revoked during the turn cannot write. Reads and writes are both included. `config.mcp_tools` is `:write` by default, `:read` for read-only tools, or `:off` to send none. The tools this gem registers (`list_agent_chats`, `create_agent_chat`, `read_agent_chat`, `append_agent_chat`, `list_agent_items`, and `read_agent_item`) are left out, so a tool call cannot open another chat turn. Each call runs in this process through `RecordingStudioMcp::Dispatcher` as the person who is signed in for this request, then the result is posted back to the hosted session. The Accessible check uses that person's grant. A generic update stores that person as the event actor and as `authorized_by`. The grant does not set an API client, so the event has no impersonator. API 0.20 writes the access-grant actor onto that event. An older API leaves the actor empty and still stores `authorized_by` when it supports that stamp. API 0.21.2 stores an in-process create, which has no API client, under `actor:<Type>:<id>`. The chat still sends `idempotency_key: call_id`. A grant with neither a client nor an actor raises `AuthorizationError`. At boot, when `config.mcp_tools` is `:write` and the installed `recording_studio_api` is older than 0.21.2, this gem logs a warning that in-process creates need 0.21.2 and that the host should upgrade. It does not raise. Set `config.mcp_tools` to `:read` or `:off` to skip that warning. A call the grant does not allow comes back as an error result. The tool output is not raised out of the turn. The same call is counted in the MCP usage log, and it uses the API read or write rate limit. Chat tool rate limits call `RecordingStudioApi::RateLimit.check` with `fail_closed: true`. The key layout stays `{namespace}:{api_read|api_write}:{identifier}:{window}`, default namespace `recording_studio_api`. A missing Redis or a Redis error limits the call even when the host fail-closed settings are off. Any other error from that check propagates. While API access is disabled, the call returns an error and does not run. A host without MCP sends no tools, and the chat behaves as before. Tool definitions are fixed when the chat is created. Turning tools off, or down to read-only, still applies to calls on a chat that was opened earlier. A dropped model stream that is still waiting on tool calls is answered from the recovered calls. If posting those results times out, the pending calls are read again before a retry, because the first post may still be in flight. One provider turn answers at most 8 rounds of tool calls. A resumed, recovered, or retried stream counts rounds already recorded for that turn id, then refuses the next call. If the run is still waiting, it is cancelled and the chat shows a failure. `config.mcp_max_writes_per_turn` (default 3) counts write calls for that same turn id, including writes already recorded. `config.mcp_tool_allow` and `config.mcp_tool_deny` limit which calls run. An empty allow list blocks every tool. See [Security](#security). `config.mcp_tools` stays `:write` unless the host sets it.

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

### Out of credits

When Recording Studio AI raises `RecordingStudioAI::Errors::UsageDeclined` (`usage_declined`) on `threads.create` or `threads.add_user_message`, the response is `200` with a server-sent stream. The person's words stay on screen, then an assistant line says the message was not sent. Nothing from that turn is stored. A refresh shows the threads and items that were already saved, and the declined line is gone. A provider contract error during that save is also an error event on the `200` stream, after the same opening events, and it stores nothing. The error object is `type` `error`, `code` `custom`, the message, and `allow_retry` `false`.

A new chat has no thread. The stream uses a random id that is not a recording id. `threads.get_by_id` answers 404.

The same notice is sent when the decline arrives after the turn has started.

`config.out_of_credits_url` is a string or `->(request:, root_recording:) { }`. `nil` leaves the notice without a link. A string, or the lambda's result, must be `http` or `https`, or a path that starts with `/`. Any other scheme, including `javascript:`, raises. A path is joined to the request origin. ChatKit opens the `http(s)` link in a new tab.

`config.out_of_credits_label` is the link text. `nil` uses the locale (`Add credits` in English, `Ajouter des crédits` in French).

```ruby
config.out_of_credits_url = "/billing"
config.out_of_credits_label = "Add credits"
```

The dummy page at `/agent-chat` uses the same helper. With neither key set, it shows the setup notice and does not call OpenAI.

## Popup

`recording_studio_agents_launcher` puts a FlatPack `FloatingFrame` on the host layout. It opens the popup through `RecordingStudioAgents::Engine.routes`, so the path follows the host mount (`GET /recording_studio_agents/popup` at the default mount). It is a same-site iframe. FlatPack `0.2.0` supplies that component and renders icons on the server. The root Gemfile pins `~> 0.2` (tag `v0.2.0`). The dummy pins the same tag. Hosts moving to 0.2 remove the manual `flat_pack/heroicons` importmap pin and any `flat-pack--icon` controller registration.

```erb
<%= recording_studio_agents_launcher %>
```

A host on the Recording Studio default layout overrides that layout and adds the same call after `yield`. The dummy does this in `test/dummy/app/views/layouts/recording_studio/default_layout.html.erb`:

```erb
<%= render "recording_studio/shared/default_layout" do %>
  <%= yield %>
  <%= recording_studio_agents_launcher %>
<% end %>
```

The launcher sits at the bottom left. The framed page has no padding, so the chat meets the panel edges. The iframe sandbox is `allow-scripts allow-same-origin allow-forms allow-popups allow-top-navigation-by-user-activation`, and `allow` is `clipboard-write`. Sign in uses `target: "_top"`. That sandbox token lets the click leave the frame.

The launcher root has a stable id, `recording_studio_agents_launcher`, and `data-turbo-permanent`. Turbo Drive keeps that node, so the iframe does not reload and an open thread stays open. The helper includes `recording_studio_agents/page_context.js` and `recording_studio_agents/launcher.js`. The launcher script puts an open panel back after the visit. The host page has to run Turbo and leave both scripts in place. Without the launcher script, the iframe stays and the panel closes.

```erb
<%= recording_studio_agents_launcher(label: "Ask", title: "Studio chat", position: :bottom_right) %>
```

`label` names the launcher. `title` is the panel heading and the iframe name. `icon` is the launcher icon. `position` is `:bottom_left` (the default), `:bottom_right`, `:top_left`, or `:top_right`. A keyword on that call wins over the config below.

`config.launcher_label` defaults to `"Open chat"`. `config.launcher_icon` defaults to `:chat` (the chat bubble). `config.popup_title` defaults to `"Chat"` and is the panel heading and the iframe name. Set `popup_title` and the popup document `<title>` uses that text too. Leave it unset and the document title stays the locale string (`Chat` in English, `Discussion` in French).

```ruby
config.launcher_icon = :sparkles
config.launcher_label = "Ask the studio"
config.popup_title = "Studio chat"
```

`config.launcher` defaults to on. It accepts `true`, `false`, or a lambda that takes the controller. `false` renders nothing. The lambda runs on each render, after the actor and workspace checks, and renders the launcher when it returns a truthy value. `config.enabled` is checked before any of that. `false` renders nothing even when `config.launcher` is `true`.

The helper also renders nothing when `config.request_actor` or `config.request_root` returns nothing. ChatKit and the popup use those same resolvers. A signed-out page has no launcher. A signed-in person with no workspace has no launcher.

```ruby
config.launcher = false
config.launcher = ->(controller) { controller.controller_path.start_with?("workspaces") }
```

The popup and the host page have to be on the same site. The helper does not read or change the session cookie. The page renders `recording_studio_agents_chatkit` in a bare layout that fills the frame. The workspace still comes from `config.request_root` (Root Switchable's current root). A signed-in person with no workspace sees an empty state instead of the chat.

### Page context

When the panel opens, and on every `turbo:load`, the launcher posts the host page into the popup iframe. `targetOrigin` is `window.location.origin`. The popup accepts the message only when `event.origin` is its own origin and `event.source` is `window.parent`. It keeps the latest accepted message and does not reload the iframe, so the open thread stays. The next chat request sends that data in the `X-Recording-Studio-Agents-Page` header. The header is data. There is no client `instructions` field.

The message carries:

- the current URL, capped at 2048 characters
- `document.title`, capped at 300 characters
- the selection from `window.getSelection()` at send time, capped at 2000 characters
- an optional page id
- an optional metadata object, capped at 2048 JSON characters

The server checks the header again, drops anything past those caps, and ignores a page id the signed-in person cannot view. A page id that is visible through Accessible parents a new chat. The open chat is not moved and is not replaced. The next turn of that same thread gets a server-built preface in the model input. The stored message stays the person's words.

The preface also includes a recording index: the page, its parent, viewable siblings and children, and nearby recordings in the same root. Each entry is JSON with `id`, `type`, and `name` when `config.recording_names` maps that class to a column. The default map is `RecordingStudioAgents::Session` => `title`. Set the host's types there (`"Page" => "title"`, `"PressKit" => "name"`). An unmapped type is id and type only. The list stops at 25 entries and 4096 bytes. Names are stripped of control characters, capped at 80 characters, and kept inside `<recording-index>`. The lines above the block say the titles are user content and that tools are the source of truth. A recording is included only when `RecordingStudioAccessible.authorized_recordings` returns it for this root (one read per index). A turn grant that is not the root still uses that grant. Access rows are left out. `phase=page_context` logs `index_n=` and `index_ms=` and does not log the names.

Set the page id on the host page with either of these:

```html
<body data-recording-studio-agents-page-recording-id="00000000-0000-4000-8000-000000000000">
<meta name="recording-studio-agents-page-recording-id" content="00000000-0000-4000-8000-000000000000">
```

The data attribute wins when both are present. The id is a recording id the person can view. Anything else is ignored, and the chat stays on the workspace.

Set metadata as JSON on one element. Keys are short words, numbers, and underscores. Values are strings, numbers, or booleans. A key named `instructions` is rejected.

```html
<body data-recording-studio-agents-page-metadata='{"section":"kits","published":true}'>
```

The launcher does not read or set the session cookie. `postMessage` does not send it. The popup and `POST /chatkit` still use the host session because the frame is same-site, which is unchanged. Cross-site framing stays unsupported. `frame-ancestors` is unchanged.

The bare layout loads `config.popup_stylesheet`, which defaults to the host `tailwind` stylesheet. Set it to another asset name, or to `nil` to skip the tag. FlatPack's empty state uses utility classes, and this document does not inherit the host page's CSS. The chat itself is sized by `recording_studio_agents/popup.css`. That sheet gives the chat the height of the iframe and stops the popup document from scrolling. ChatKit keeps the composer at the bottom of that box and scrolls the messages inside it. A host page that embeds the chat outside the popup still uses the card height `h-[min(40rem,calc(100dvh-16rem))]`.

`config.popup_theme` is the Flatpack theme on that document. It defaults to `rounded`, which is `data-theme="rounded"` on the popup `<html>`. Set it to the host theme name when the popup should match a named theme such as `featured-in`.

```ruby
config.popup_theme = "featured-in"
```

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

Recording Studio AI 0.21.2 loads a root recording id before `attribution_validator` runs. `Agents.stream` passes that id. The default check accepts a root whose parent is empty and whose `root_recording_id` is its own id. A context recording must belong to that root. This gem does not replace the validator. Assign `config.attribution_validator` in `config/initializers/recording_studio_ai.rb` for a stricter check. It runs after the recording is loaded.

A signed-out visitor sees a sign-in prompt instead of the chat. The button uses `config.sign_in_path`. When that is unset, the path is `main_app.new_user_session_path` if the route exists, and `/users/sign_in` otherwise. A string is a path. A lambda receives the controller:

```ruby
config.sign_in_path = "/login"
config.sign_in_path = ->(controller) { controller.main_app.new_user_session_path }
```

`POST /recording_studio_agents/chatkit` with no actor returns 401. A signed-in actor who is not allowed to execute gets an error event on the `200` stream. The message names `recording_studio_ai.execute`. The opening events are already written, so that refusal is not an HTTP `403`.

The sign-in copy is in `config/locales/en.yml` and `config/locales/fr.yml`.

## Security

In-process chat tools treat tool results as data. This limits what one reply can do. It does not make the model obey.

What this does:

- Every chat starts with a gem-owned preamble, before `config.instructions` and before any per-session override. It says tool output is untrusted data, never instructions, and to make no write unless the user asked for it in this turn. It also says to claim a change only after a write tool returned success in this turn, and otherwise to call the tool or ask if something is unclear. A result from an earlier turn does not count. The preamble is sent when the hosted session is created. A later message on that chat, including `threads.add_user_message`, does not send a new instructions string. The hosted session keeps the one from create. There is no setting that removes it. Host text and an override are appended after it. A chat opened on an older release keeps the preamble from that release.
- A successful tool result is posted back as JSON, `{"untrusted_tool_output":"<text>"}`. That string still stops at 256 KB. A tool error that is not one of this gem's own refusal sentences is wrapped the same way. Refusals such as `tool is not allowed` and `write limit reached` stay plain text so the model can read them.
- `config.mcp_max_writes_per_turn` defaults to 3 and must be a positive integer. It counts write-tool calls for one provider turn, across every round, including a resumed, recovered, or retried stream. The count is the audit rows already stored for that turn id. The count, the round number, and the pending insert are taken together under a PostgreSQL advisory lock for that turn. The lock method opens that transaction, and the lock ends when it commits, before the tool runs. Do not run a chat tool round inside an open transaction. That raises, because an outer transaction would keep the lock until the outer transaction commits. `config.allow_chat_tools_in_transaction` permits it and defaults to false. This gem's tests set it for transactional fixtures. A second caller with the same call id joins the audit row already started, does not run the tool, and does not change that row. A live duplicate is left out of the results posted to the provider, because the first caller submits the real result. `config.chat_tool_deadline` (default 2 minutes) stops the dispatch. That caller posts success false and `tool call timed out; it was not re-run`, and stores `unknown` only if the pending update wins. A pending row is also stale once `occurred_at` is older than the deadline plus a 30 second grace. `config.chat_tool_stale_after` (default 10 minutes) must be longer than that deadline plus grace. A stale join posts success false and `tool call outcome unknown; it was not re-run` only if that same update wins. A live duplicate is left out of the post, and that round ends with no ChatKit event. Other database adapters raise. When `config.mcp_tools` is not `:off`, boot reads the database adapter from the connection config, without opening a connection, and raises unless it is PostgreSQL. No database config skips that check. Read versus write uses Recording Studio MCP `ToolSurface#read_only_tool?`. A later write in that turn is answered with `write limit reached`. The turn continues, and reads are still answered. The 8-round cap uses the same lock and the same turn id. `config.mcp_tools` stays `:write` by default. `:read` and `:off` are unchanged.
- `config.mcp_tool_allow` and `config.mcp_tool_deny` are arrays of tool names, or nil. They apply when the function list is built and again when a call runs. Deny wins. When allow is set, only those names are listed or called. Nil means no extra name filter. An empty allow list blocks every tool: none are listed, and every call is refused.
- Each chat tool call writes one row to `recording_studio_agents_chat_tool_audits` before the tool runs, with outcome `pending`, then updates that outcome. A crash mid-call leaves `pending`. Recording Studio Logs registers that table (`retention: :indefinite`, no partition, no summary). The row stores the actor type and id, the chat recording id, the provider turn id, the round number, the tool name, `read` or `write`, up to 50 argument keys, the outcome (`pending`, `ok`, `error`, `refused`, `limited`, or `unknown`), and the call id. A unique index on provider turn id and call id keeps one row per call in a turn. Null turn ids stay distinct. A key is kept only when it is identifier-like and at most 64 characters; a longer identifier is truncated to 64, and anything else is dropped. It does not store argument values.

What this does not do:

- It does not stop a model from ignoring the preamble.
- It does not ask the person to approve a write.
- It does not read MCP tool annotations.
- It does not rewrite the words inside a tool result, beyond the envelope and the size cap.
- It does not cover MCP calls made outside this chat, including `list_agent_chats`, `create_agent_chat`, `read_agent_chat`, `append_agent_chat`, `list_agent_items`, and `read_agent_item`.

## Dummy app

The dummy app validates the engine in a host with Recording Studio Users, Oauth, MCP, FlatPack, and Recording Studio's default layout. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. ChatKit keeps that session. MCP at `/recording_studio_mcp` uses an Oauth bearer token.

The dummy also has press kits at `/press_kits`. A kit is a recordable with the agents capability, so a chat can be scoped to it, and Attachable dummy GitHub tag `v0.31.0` stores its photos. That pin lives in the dummy Gemfile only. It is not a gemspec dependency. MCP `list`, `show`, and `update` on type `PressKit` read and edit kits in the granted workspace. A successful generic `update` stores the access-grant actor. In the dummy that is the OAuth authorization, and the OAuth client is the impersonator. `create_agent_chat` stores the OAuth client as the event actor. Both store the approving person in `authorized_by_type` and `authorized_by_id`. A client that sends `authorized_by_type`, `authorized_by_id`, or `metadata` on `update` is refused, because those are not writable fields. The same arguments on `create_agent_chat` are dropped, and the stored event keeps the server stamp.

## MCP

The gem registers the chat endpoints when the host has loaded Recording Studio API. OpenAPI summaries and descriptions for those endpoints come from `RecordingStudioAgents::Api::ToolCopy` and describe the HTTP call. When Recording Studio MCP is also loaded, `RecordingStudioAgents::McpCopy::Copy` supplies the tool text and the gem registers the same calls with `register_tool(endpoint:)`. MCP stays optional. Each tool's `openapi` hash includes a success JSON schema and example so MCP docs can show sample output. The host mounts MCP, API, and Oauth and draws the protected-resource metadata. Add the tool names to the MCP server. A server that omits them does not advertise the chat tools. `describe` stays. Generic tree tools stay off this list. Include those separately when the host still wants `list`, `show`, `create`, `update`, or `delete`, and call `register_type` for each recordable they should cover.

```ruby
RecordingStudioMcp.register_server(:public, api: :public) do
  include_tools(*RecordingStudioAgents::McpCopy.tool_names)
end
```

The names are `list_agent_chats`, `create_agent_chat`, `read_agent_chat`, `append_agent_chat`, `list_agent_items`, and `read_agent_item`. The 0.20 names `agent_chats_list`, `agent_chats_create`, `agent_chats_read`, `agent_chats_append`, `agent_items_list`, and `agent_items_read` are gone.

A bearer token acts in the workspace on its access grant. The browser switcher and a session cookie on the same request do not change that grant. Reads call `access_grant.authorize!` with `:view`. Writes call it with `:edit`. The catalog still uses the grant's `OauthAuthorization` for visibility. `create_agent_chat` records the OAuth client as the event actor and the approving person in `authorized_by_type` and `authorized_by_id` when the host API provides that stamp. Client-sent copies of those keys, and a client metadata bag, are not stored. The provider attribution for the chat stays the grant actor. The generic `update` tool records the access-grant actor and the same stamp. On API 0.20 the OAuth client is the impersonator when it is a different record from that actor. It refuses a client `authorized_by_*` or `metadata` argument as an unknown field.

| Tool | What it does |
| --- | --- |
| `list_agent_chats` | Chats in the granted workspace, newest first. Optional `parent` limits the list. Optional `limit` defaults to 20 and stops at 50. There is no page cursor |
| `create_agent_chat` | Opens a chat. Requires `input` and `idempotency_key`. Returns `id` and `title`. A repeated key returns the existing chat and does not change its parent, title, message, or instructions. The call still requires a non-empty input, and a parent you pass must still be a record you can change |
| `read_agent_chat` | One chat. Returns `id`, `title`, `created_at`, and `status`. The messages are on `list_agent_items` |
| `append_agent_chat` | Adds a user message. Returns the chat `id`, not a new item id |
| `list_agent_items` | Stored messages on one chat. `order` `asc` is oldest first. Omitting it is newest first |
| `read_agent_item` | One stored message. `item_id` comes from `list_agent_items` |
