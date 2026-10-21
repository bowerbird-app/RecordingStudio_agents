# RecordingStudioAgents

Hosted agent chats for Recording Studio. A chat is a `Session` recordable owned by a root that opted into the `:agents` capability. Turns stay in Recording Studio AI. This gem stores the session binding, a local item projection, and the retention clock.

ChatKit talks to this gem. The browser embed uses the host session. MCP uses an Oauth bearer token.

## Requirements

- Ruby 3.3 or newer
- Rails 8.1
- Recording Studio `~> 4.7` (dummy GitHub tag `v4.7.0`)
- Recording Studio AI `~> 0.15.1` (dummy GitHub tag `v0.15.1`)
- Recording Studio Metrics dummy GitHub tag `v0.3.1`
- Accessible dummy GitHub tag `v0.20.0`
- Trashable dummy GitHub tag `v0.11.1`
- Root Switchable dummy GitHub tag `v0.9.5`
- Cache dummy GitHub tag `v0.5.1`
- FlatPack dummy GitHub tag `v0.1.254`
- Recording Studio Users dummy GitHub tag `v0.24.0`
- Recording Studio Oauth dummy GitHub tag `v0.12.5`
- Recording Studio MCP dummy GitHub tag `v0.19.1`
- Recording Studio API dummy GitHub tag `v0.11.4`
- Recording Studio Admin dummy GitHub tag `v2.3.3`
- Site Settings dummy GitHub tag `v0.5.1`

The provider API key stays in Recording Studio AI. This gem does not read one.

## Host setup

```ruby
gem "recording_studio_agents", github: "bowerbird-app/RecordingStudio_agents"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.7.0"
gem "recording_studio_ai", github: "bowerbird-app/RecordingStudio_AI", tag: "v0.15.1"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.3.1"
```

Register the recordable, opt a parent type into `:agents`, and copy migrations:

```ruby
RecordingStudio.configure do |config|
  config.recordable_types += ["RecordingStudioAgents::Session"]
end
```

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

Create and append are idempotent on their keys inside one root. The same create key in a different root opens a second chat. The binding stores `root_recording_id`, and the unique index is `(root_recording_id, create_idempotency_key)`. Item keys use the same pair. A repeated key inside one root still returns the existing chat or message and does not check or store a new instructions override. Two creates that overlap on that key do the same: the loser drops the extra provider session and returns the chat that won.

## ChatKit

`POST /recording_studio_agents/chatkit` accepts the ChatKit protocol and answers with JSON or server-sent events. The host session resolves the actor. The root is the workspace selected in Root Switchable (`RecordingStudio::RootSwitchable.resolve_current_root`), not the oldest workspace. Client metadata ids are ignored. Create, append, rename, and delete go through the Sessions services. Streaming, cancel, and reading a finished first turn go through `RecordingStudioAI::Agents`. A chat the actor cannot view is a 404, the same as a missing chat.

`threads.create` is not streamed by Recording Studio AI. After the session is saved, the endpoint reads the provider stream, and reads saved items when that stream has no text. `text_delta` events become ChatKit text deltas. An unsupported operation returns a protocol error.

`recording_studio_agents_chatkit` renders the official `<openai-chatkit>` web component from `https://cdn.platform.openai.com/deployments/chatkit/chatkit.js`. Its custom backend is this endpoint. The component's `fetch` sends the session cookie and the CSRF token. `domainKey` comes from `config.chatkit_domain_key`. The inline script assigns `endpoint`, `domainKey`, and `hostOptions` from JSON literals, so a quote in any of those values stays a quote the browser can parse. The browser does not receive an OpenAI API key, a client secret, or an Agent Builder workflow.

Pass `page_recording:` with the page's recording to scope that embed to the page. The helper adds `page_recording_id` to the endpoint. The server loads that recording again, checks it sits inside the current workspace, and checks the actor can view it. A missing or cross-workspace id is a 404. An id inside the workspace that the actor cannot view is a 403. With a valid id, new chats use that recording as their parent and `threads.list` returns only those chats. Leave it off and the endpoint behaves as before: new chats belong to the workspace and the list includes every chat in it. The same checks apply to MCP `parent` on `agent_chats_list` and `agent_chats_create`. Omit `parent` and those tools keep the workspace behavior. A parent can own a chat only when its type includes `RecordingStudio::Capabilities::Agents`. The dummy `Page` model opts in that way. A folder still cannot.

`chatkit_options:` is merged over `config.chatkit_options` and sent to `setOptions`. The config value is a hash, or a lambda called with the controller and `config.purpose`. Use the ChatKit keys you need: `startScreen` (greeting and prompts with `label`, `prompt`, and optional `icon`), `theme`, `header`, `composer` (`placeholder`), `history`, and `initialThread`. `setOptions` replaces the previous options, so the frame always sets `api` itself. A host `api` key is dropped. `initialThread: nil` keeps the new-thread start screen. One host declaration can pass the same page into `page_recording:` and the start screen into `chatkit_options:`. The dummy page at `/agent-chat/page` does that for the Press kit page. `/agent-chat` stays the workspace chat.

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

## Dummy app

The dummy app validates the engine in a host with Recording Studio Users, Oauth, MCP, FlatPack, and Recording Studio's default layout. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. ChatKit keeps that session. MCP at `/recording_studio_mcp` uses an Oauth bearer token.

## MCP

The gem registers the chat tools when the host has loaded Recording Studio API, and the `agent-chats` skill when the host has loaded Recording Studio MCP. The host mounts MCP, API, and Oauth and draws the protected-resource metadata. A bearer token acts in the workspace on its access grant. The browser switcher and a session cookie on the same request do not change that grant. Reads call `access_grant.authorize!` with `:view`. Writes call it with `:edit`. Chats opened over MCP are attributed to the grant's `OauthAuthorization`.

| Tool | What it does |
| --- | --- |
| `agent_chats_list` | Chats in the granted workspace. Optional `parent` limits the list to that parent |
| `agent_chats_create` | Opens a chat. Requires `input` and `idempotency_key`. Optional `parent` chooses the parent |
| `agent_chats_read` | One chat |
| `agent_chats_append` | Adds a user message |
| `agent_items_list` | Items on one chat |
| `agent_items_read` | One item |

`skill://agent-chats/SKILL.md` is the MCP resource for those tools.
