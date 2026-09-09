# Dummy host

This Rails app exists to prove Recording Studio Agents in a real host.

## What it covers

- Devise authentication with a seeded admin user (`admin@admin.com` / `Password`)
- Workspace, Folder, and Page with Accessible grants
- An Admin root for Recording Studio Admin. The Agents hub shows attempts, tokens, and hungry agents for Last 4 weeks. Runs and Usage by agent join Recording Studio AI for token and tool counts, and default the date filter to Last 4 weeks.
- The workspace switcher lists workspaces the signed-in user can access.
- Page librarian demo on `/` (`POST /agents/demo`). After a run, home lists what it did. Workspace outline knowledge cites the workspace root. The demo passes the Getting Started page as context inside that workspace.
- Support clerk registered for optional skill and pack tests (no second home button)
- Mounted Agents, AI, Accessible, and Admin (`/admin`)

## Quick start

```bash
cd test/dummy
bundle install
bin/rails db:setup
bin/dev
```

Run those commands from the dummy app directory.

## Useful routes

- `/` - page librarian demo, with steps after a run
- `/users/sign_in` - Devise sign-in
- `/admin` - Agents admin, including Agents, Runs, and Usage by agent. Agent names open a details page.
- `/recording_studio` - redirects to `/`
- `/up` - health check

Authenticated pages use Recording Studio's shared default layout. Devise sign-in keeps `layouts/application`. Admin screen tables lazy-load through Turbo frames. The dummy importmap pins Turbo and Recording Studio Admin controllers so those frames fill.

`bin/rails tailwindcss:build` writes Bundler gem `@source` paths first, then compiles. Without that step, layout and Admin table utilities are missing from the CSS.
