---
name: agent-chats
description: List, create, read, and continue hosted agent chats in the connected workspace.
---

# Agent chats

Tools act on the workspace in the bearer token's access grant.

- `agent_chats_list` lists chats in that workspace.
- `agent_chats_create` opens a chat. Send `input` and `idempotency_key`.
- `agent_chats_read` reads one chat by id.
- `agent_chats_append` adds a user message. Send `id`, `input`, and `idempotency_key`.
- `agent_items_list` and `agent_items_read` read the local item projection.

The same `idempotency_key` can be used again in a different workspace. Inside one workspace it returns the existing chat or message.
