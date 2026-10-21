---
name: agent-chats
description: List, create, read, and continue hosted agent chats in the connected workspace.
---

# Agent chats

Tools act on the workspace in the bearer token's access grant.

- `agent_chats_list` lists chats in that workspace. Optional `parent` limits the list to chats whose parent is that recording. Omit it to list the whole workspace.
- `agent_chats_create` opens a chat. Send `input` and `idempotency_key`. Optional `parent` opens the chat under that recording instead of the workspace. The parent must be inside the workspace and viewable, and creating still needs edit access on it. `instructions` is an optional string of at most 4000 characters. Blank uses the host default. A real override is rejected unless the host set `config.instructions_override` to `:admin` or `:edit`. When it is allowed, the text is appended after the host default. Sending the same key again returns the existing chat and does not check a new override. ChatKit does not accept this field.
- `agent_chats_read` reads one chat by id.
- `agent_chats_append` adds a user message. Send `id`, `input`, and `idempotency_key`.
- `agent_items_list` and `agent_items_read` read the local item projection.

The same `idempotency_key` can be used again in a different workspace. Inside one workspace it returns the existing chat or message. While an older global unique index is still in place, a key already stored in another workspace is an input error that names that clash. A missing chat stays "chat was not found".
