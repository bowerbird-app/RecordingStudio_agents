# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- ChatKit `POST /chatkit` endpoint. It speaks the ChatKit thread protocol over JSON and server-sent events, checks Accessible access, and calls Sessions services plus Recording Studio AI. The first turn is read from the provider stream, and from saved items when that stream has no text, because create is not streamed.
- `recording_studio_agents_chatkit` renders the official `<openai-chatkit>` component against that endpoint, with the session cookie, CSRF token, and `config.chatkit_domain_key`. When `OPENAI_API_KEY` or `CHATKIT_DOMAIN_KEY` is missing, it renders a setup notice.

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
