# Project Guidelines

## Architecture

- This repository is the Recording Studio Agents Rails engine.
- Preserve engine namespace isolation under `RecordingStudioAgents`.
- Treat `docs/gem_template/` as architectural reference material from the original template. For current addon workflow, prefer the top-level README and the dummy app.
- Keep changes small and scoped.

## UI Conventions

- FlatPack is the default UI system for this repo.
- The approved UI reference is the live FlatPack demo app at https://flatpack-c6p8f.ondigitalocean.app/ when you need to inspect current shared components and patterns.
- Start with the FlatPack demo app's table of components to quickly discover available UI building blocks before inventing custom markup.
- When editing ERB views, prefer `render FlatPack::...` components over custom HTML when an equivalent component exists.
- Prefer standardized and testable FlatPack ViewComponents over one-off ERB markup or custom JavaScript.
- Treat user-provided FlatPack demo URLs as task context and use them to guide implementation, explanation, or planning.
- Keep custom markup limited to semantic wrappers or content that FlatPack does not cover.
- In Codespaces or other restricted environments, the user may need to enable access to that URL before you can inspect it.
- If the FlatPack demo app is not reachable, clearly say that access to that URL is unavailable and ask the user to enable access or provide sanitized screenshots, copied markup, or component details instead of guessing.
