# RecordingStudioAgents

Hosted agent chats for Recording Studio. A chat is a `Session` recordable owned by a root that opted into the `:agents` capability. Turns stay in Recording Studio AI. This gem stores the session binding, a local item projection, and the retention clock.

ChatKit talks to this gem. The browser embed uses the host session. MCP uses an Oauth bearer token.

## Requirements

- Ruby 3.3 or newer
- Rails 8.1
- Recording Studio `>= 6.1.0` (dummy GitHub tag `v6.1.0`)
- Recording Studio AI `~> 0.19.0` (dummy GitHub tag `v0.19.1`)
- Recording Studio Metrics dummy GitHub tag `v0.7.0`
- Accessible dummy GitHub tag `v0.20.0`
- Trashable dummy GitHub tag `v0.11.3`
- Root Switchable dummy GitHub tag `v0.9.7`
- Cache dummy GitHub tag `v0.5.1`
- FlatPack `>= 0.1.315` (dummy commit `1fcbafe94f8eb118f0a22182f63f5110fcc97a56`, version 0.1.319)
- view_component `>= 4.14`, `< 5` (this repository locks `4.19.0`)
- Recording Studio Users dummy GitHub tag `v0.25.2`
- Oauth dummy GitHub tag `v0.15.1`
- Recording Studio MCP dummy GitHub tag `v0.22.0`
- Recording Studio API dummy GitHub tag `v0.16.0`
- Recording Studio Logs dummy GitHub tag `v0.7.1`
- Recording Studio Admin dummy GitHub tag `v2.3.3`
- Site Settings dummy GitHub tag `v0.5.1`

Hosts that want the OAuth client on MCP event rows need Recording Studio MCP >= 0.22, API >= 0.16, and Oauth >= 0.15.1. This gem does not depend on those gems. An older API keeps the access-grant actor on the event and omits `authorized_by_type` and `authorized_by_id`.

The provider API key stays in Recording Studio AI. This gem does not read one.

## Host setup

```ruby
gem "recording_studio_agents", github: "bowerbird-app/RecordingStudio_agents"
gem "flat_pack", github: "bowerbird-app/flatpack", ref: "1fcbafe94f8eb118f0a22182f63f5110fcc97a56"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.1.0"
gem "recording_studio_ai", github: "bowerbird-app/RecordingStudio_AI", tag: "v0.19.1"
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.7.1"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.7.0"
gem "view_component", "4.19.0"
```

Recording Studio AI `v0.19.1`, Metrics `v0.7.0`, and Logs `v0.7.1` allow Recording Studio `>= 6.1.0`. Several other dummy pins still declare `recording_studio` below 5, including Trashable `v0.11.3`, Users `v0.25.2`, Root Switchable `v0.9.7`, Attachable `v0.20.2`, API, Oauth, MCP, Site Settings, and Cache. Both Gemfiles load `test/support/widen_recording_studio_requirement.rb` before Bundler reads gemspecs. That file rewrites a `recording_studio` requirement that rejects 6.1.0 into `>= 6.1.0`. It is not part of the installed gem. A host Gemfile that includes one of those older gems has to widen the requirement the same way.

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

```ruby
class Workspace < ApplicationRecord
  include RecordingStudio::Capabilities::Agents.to
end
```

```bash
bin/rails generate recording_studio_agents:migrations
bin/rails db:migrate
```

Schedule `RecordingStudioAgents::ExpireSessionsJob`. It closes chats whose `expires_at` has passed. Closing deletes the provider session through Recording Studio AI first. An already-gone provider session is success, and the local chat, items, and binding are removed. A different provider failure leaves the local rows in place for a later retry.

## Services

- `RecordingStudioAgents::Sessions::Create` opens a provider session, then records the chat under the parent.
- `RecordingStudioAgents::Sessions::Append` sends another user message and refreshes the retention clock.
- `RecordingStudioAgents::Sessions::Rename` revises the chat title. The previous snapshot stays.
- `RecordingStudioAgents::Sessions::Close` deletes the provider session, then purges the local chat.
- `RecordingStudioAgents::Sessions::Expire` closes every expired binding. One failure does not stop the rest. Expiry is system cleanup scoped to the recording and its root. It does not use the creator and does not check access. A user `Close` still requires edit access on the chat.

A chat stores the instructions it was opened with. The host default is `config.instructions`. A per-chat override is appended after that default, with a blank line between them, and never replaces it. `config.instructions_override` defaults to `:none`, so a real override is rejected and the chat is not created. A host opts in with `:admin` (Recording Studio Accessible admin on the workspace) or `:edit`. Blank or whitespace-only text uses the host default. The override must be a string no longer than `config.max_instructions_length` (4000). ChatKit `threads.create` does not accept `instructions`; a client that sends the field gets a 400. MCP `agent_chats_create` and host Ruby (`Sessions::Create`) can pass it when the config allows it. The stored copy is personal data. The engine adds an exact `instructions` filter to `filter_parameters`, and the chat record filters its own `instructions` attribute, so request logs and `inspect` do not show it. A host parameter such as `shipping_instructions` is not filtered. The 30-day cleanup deletes those stored instructions with the chat.

Create and append are idempotent on their keys inside one root. The same create key in a different root opens a second chat. The binding stores `root_recording_id`, and the unique index is `(root_recording_id, create_idempotency_key)`. Item keys use the same pair. A repeated key inside one root still returns the existing chat or message. That replay does not check a new parent and does not check or store a new instructions override. Two creates that overlap on that key do the same: the loser drops the extra provider session and returns the chat that won.

## ChatKit

`POST /recording_studio_agents/chatkit` accepts the ChatKit protocol and answers with JSON or server-sent events. The host session resolves the actor. The root is the workspace selected in Root Switchable (`RecordingStudio::RootSwitchable.resolve_current_root`), not the oldest workspace. Client metadata ids are ignored. Create, append, rename, and delete go through the Sessions services. Streaming, cancel, and reading a finished first turn go through `RecordingStudioAI::Agents`. A chat the actor cannot view is a 404, the same as a missing chat.

`threads.create` is not streamed by Recording Studio AI. After the session is saved, the endpoint reads the provider stream, and reads saved items when that stream has no text. `text_delta` events become ChatKit text deltas. An unsupported operation returns a protocol error.

`recording_studio_agents_chatkit` renders the official `<openai-chatkit>` web component from `https://cdn.platform.openai.com/deployments/chatkit/chatkit.js`. Its custom backend is this endpoint. The component's `fetch` sends the session cookie and the CSRF token. `domainKey` comes from `config.chatkit_domain_key`. The inline script assigns `endpoint`, `domainKey`, and `hostOptions` from JSON literals, so a quote in any of those values stays a quote the browser can parse. The browser does not receive an OpenAI API key, a client secret, or an Agent Builder workflow. The panel sits in a FlatPack card. Its height is the Tailwind class `h-[min(40rem,calc(100dvh-16rem))]`, so the host Tailwind build has to scan this gem's views. An inner wrapper uses the card radius and `overflow-hidden` so the ChatKit iframe follows the rounded corners.

Pass `page_recording:` with the page's recording to scope that embed to the page. The helper adds `page_recording_id` to the endpoint. The server loads that recording again, checks it sits inside the current workspace, and checks the actor can view it. A missing or cross-workspace id is a 404. An id inside the workspace that the actor cannot view is a 403. With a valid id, new chats use that recording as their parent and `threads.list` returns only those chats. Leave it off and the endpoint behaves as before: new chats belong to the workspace and the list includes every chat in it. The same checks apply to MCP `parent` on `agent_chats_list` and `agent_chats_create`. Omit `parent` and those tools keep the workspace behavior. A parent can own a chat only when its type includes the agents capability:

```ruby
include RecordingStudio::Capabilities::Agents.to
```

The dummy `Page` model uses that line. A folder still cannot. A trashed page is treated as missing. A present id that is not a string, such as `page_recording_id[]`, is a 404. An id whose type cannot hold a chat is a 422.

`chatkit_options:` is merged over `config.chatkit_options` and sent to `setOptions`. The config value is a hash, or a lambda of 0, 1, or 2 arguments. Zero arguments are called with none. One argument receives the controller. Two arguments receive the controller and `config.purpose`. The lambda is not called when the setup notice is showing. Use the ChatKit keys you need: `startScreen` (greeting and prompts with `label`, `prompt`, and optional `icon`), `theme`, `header`, `composer` (`placeholder`), `history`, and `initialThread`. `setOptions` replaces the previous options, so the frame always sets `api` itself. A host `api` key is dropped. `initialThread: nil` keeps the new-thread start screen. One host declaration can pass the same page into `page_recording:` and the start screen into `chatkit_options:`. The dummy page at `/agent-chat/page` does that for the Press kit page. `/agent-chat` stays the workspace chat.

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

Mount the engine, then open `GET /recording_studio_agents/popup` (`recording_studio_agents.popup_path`). Point Embeddable's floating launcher iframe at that URL. The page lives in Agents and renders `recording_studio_agents_chatkit` in a bare layout that fills the iframe. It does not use Embeddable's `FloatingWidget::Interactive`, and it does not take a page. The chat uses the workspace from `config.request_root` (Root Switchable's current root).

Pass `fill: true` to the helper when a host screen should use the same full-height chat. The popup does that. Other screens keep the card height.

### Framing and content security policy

Only the popup action sets a content security policy. The rest of the app keeps its own policy. The popup allows the ChatKit script (`https://cdn.platform.openai.com`), connections to that host and `https://api.openai.com`, and a frame from the ChatKit host. `frame-ancestors` is `'self'` plus `config.chatkit_allowed_origins`. The action drops `X-Frame-Options` so those origins can frame the page.

The default origins are `http://localhost:3000` and `http://127.0.0.1:3000`. Add staging and production later in the initializer, or with `CHATKIT_ALLOWED_ORIGINS` (comma-separated, scheme and port included):

```ruby
config.chatkit_allowed_origins = ENV["CHATKIT_ALLOWED_ORIGINS"] if ENV["CHATKIT_ALLOWED_ORIGINS"].present?
config.chatkit_domain_key = ENV["CHATKIT_DOMAIN_KEY"].presence
```

Register those same origins in the [OpenAI domain allowlist](https://platform.openai.com/settings/organization/security/domain-allowlist) and put the domain key in `CHATKIT_DOMAIN_KEY`. An origin must be an `http` or `https` origin with no path.

### Who can run an agent

Recording Studio AI denies every action until the host sets `authorization_handler`. A denied `recording_studio_ai.execute` used to raise on the first message. Allow that one action for any signed-in actor. In `config/initializers/recording_studio_ai.rb`:

```ruby
config.authorization_handler = RecordingStudioAgents::SignedInAuthorization.method(:call)
```

The handler returns true only when the action is `recording_studio_ai.execute` and the attribution has an initiator. Other AI actions stay denied. The dummy app sets this. Copy it into the host. It does not replace Recording Studio Accessible: creating a chat still needs edit access on the workspace.

A signed-out visitor sees a sign-in prompt instead of the chat. The button uses `config.sign_in_path`, which defaults to `/users/sign_in`. A string is a path. A lambda receives the controller:

```ruby
config.sign_in_path = "/users/sign_in"
config.sign_in_path = ->(controller) { controller.main_app.new_user_session_path }
```

`POST /recording_studio_agents/chatkit` with no actor returns 401. A signed-in actor who is not allowed to execute returns 403.

The sign-in copy is in `config/locales/en.yml` and `config/locales/fr.yml`.

## Dummy app

The dummy app validates the engine in a host with Recording Studio Users, Oauth, MCP, FlatPack, and Recording Studio's default layout. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. ChatKit keeps that session. MCP at `/recording_studio_mcp` uses an Oauth bearer token.

The dummy also has press kits at `/press_kits`. A kit is a recordable with the agents capability, so a chat can be scoped to it, and Attachable dummy GitHub tag `v0.20.2` stores its photos. That pin lives in the dummy Gemfile only. It is not a gemspec dependency. MCP `list`, `show`, and `update` on type `PressKit` read and edit kits in the granted workspace. A successful generic `update` and `agent_chats_create` both store the OAuth client as the event actor and the approving person in `authorized_by_type` and `authorized_by_id`. A client that sends `authorized_by_type`, `authorized_by_id`, or `metadata` on `update` is refused, because those are not writable fields. The same arguments on `agent_chats_create` are dropped, and the stored event keeps the server stamp.

## MCP

The gem registers the chat tools when the host has loaded Recording Studio API, and the `agent-chats` skill when the host has loaded Recording Studio MCP. The host mounts MCP, API, and Oauth and draws the protected-resource metadata. A bearer token acts in the workspace on its access grant. The browser switcher and a session cookie on the same request do not change that grant. Reads call `access_grant.authorize!` with `:view`. Writes call it with `:edit`. The catalog still uses the grant's `OauthAuthorization` for visibility. `agent_chats_create` records the OAuth client as the event actor and the approving person in `authorized_by_type` and `authorized_by_id` when the host API provides that stamp. Client-sent copies of those keys, and a client metadata bag, are not stored. The provider attribution for the chat stays the grant actor. The generic `update` tool records the same actor and stamp on a successful write. It refuses a client `authorized_by_*` or `metadata` argument as an unknown field.

| Tool | What it does |
| --- | --- |
| `agent_chats_list` | Chats in the granted workspace. Optional `parent` limits the list to that parent |
| `agent_chats_create` | Opens a chat. Requires `input` and `idempotency_key`. Optional `parent` chooses the parent. A repeated key returns the existing chat and ignores `parent` |
| `agent_chats_read` | One chat |
| `agent_chats_append` | Adds a user message |
| `agent_items_list` | Items on one chat |
| `agent_items_read` | One item |

`skill://agent-chats/SKILL.md` is the MCP resource for those tools.
