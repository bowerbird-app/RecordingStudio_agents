# Dummy host

This Rails app exists to prove Recording Studio Agents in a real host.

## What it covers

- Devise authentication with a seeded admin user (`admin@admin.com` / `Password`)
- Workspace, Folder, and Page with Accessible grants
- An Admin root for Recording Studio Admin. `/admin` is the staff hub. Agents is `/admin/sections/agents` and shows attempts, tokens, and hungry agents for Last 4 weeks. Runs and Usage by agent join Recording Studio AI for token and tool counts, and default the date filter to Last 4 weeks.
- The workspace switcher lists workspaces the signed-in user can access.
- Page librarian demo on `/` (`POST /agents/demo`). After a run, home lists what it did. Workspace outline knowledge cites the workspace root. The demo passes the Getting Started page as context inside that workspace. Studio Workspace is the example library: Product Docs (Getting Started, Invite your team, Plans and billing), Guides (Publish a page, Move a page, Leave a comment), People (Staff handbook, Time off), and a root page, Studio overview. Client Workspace and Private Workspace have no pages. Page librarian can list those titles and the menu pages (Home, Playground, Staff, Agents), then find one by title. With `GEMINI_API_KEY` or `google_ai_studio` set, that run calls Gemini. Without a generative key, it uses an offline stub.
- Decisions use TypeSafe Jev through `RecordingStudioAI.decide`. Set `TYPESAFE_API_KEY` or `typesafe`. Profiles keep Gemini on generation and `jev-latest` on decisions.
- Support clerk registered for optional skill and pack tests (no second home button)
- Playground at `/playground`. The form sits on the left and the steps on the right. Pick a registered agent, write an instruction, and search for the tools and skills that run may use. Model replies are kept. Open the model call from the steps. Admin lists model calls from workspaces as well as the staff root, so that call shows up. The dummy sets fixture Active Record encryption keys when the host has none, so that reply can be read.
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
- `/playground` - pick a registered agent, search for skills and tools, write an instruction, and watch the steps
- `/users/sign_in` - Devise sign-in
- `/admin` - staff hub, with links to Agents and model calls
- `/admin/sections/agents` - Agents admin, including Agents, Runs, and Usage by agent. Agent names open a details page. The actions menu on Agents turns an agent on or off. Skills and tools on that page open their own details.
- `/recording_studio` - redirects to `/`
- `/up` - health check

The home page uses a sidebar layout. Devise sign-in keeps `layouts/application`. Admin, the workspace switch page, and access screens use Recording Studio's shared default layout. Admin screen tables lazy-load through Turbo frames. The dummy importmap pins Turbo and Recording Studio Admin controllers so those frames fill.

`bin/rails tailwindcss:build` writes Bundler gem `@source` paths first, then compiles. Without that step, layout and Admin table utilities are missing from the CSS.
