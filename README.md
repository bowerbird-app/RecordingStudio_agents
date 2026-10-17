# RecordingStudioAgents

Hosted agent chats for Recording Studio. A chat is a `Session` recordable owned by a root that opted into the `:agents` capability. Turns stay in Recording Studio AI. This gem stores the session binding, a local item projection, and the retention clock.

ChatKit and the browser embed are not part of this release.

## Requirements

- Ruby 3.3 or newer
- Rails 8.1
- Recording Studio `~> 4.7` (dummy GitHub tag `v4.7.0`)
- Recording Studio AI `~> 0.15.1` (dummy GitHub tag `v0.15.1`)
- Recording Studio Metrics dummy GitHub tag `v0.3.1`
- Accessible dummy GitHub tag `v0.18.0`
- Trashable dummy GitHub tag `v0.10.0`
- Root Switchable dummy GitHub tag `v0.9.0`
- Cache dummy GitHub tag `v0.5.0`
- FlatPack dummy GitHub tag `v0.1.196`

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

Create and append are idempotent on their keys inside one root. Reusing a create key from another root raises `RecordingStudioAgents::IsolationError`.

## Dummy app

The dummy app validates the engine in a host with Devise, FlatPack, and Recording Studio's default layout. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`.
