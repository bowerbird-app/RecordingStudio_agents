# Dummy App

This Rails app exists to validate the Recording Studio addon template in a real host application.

## What It Covers

- Devise authentication with a seeded admin user
- `Current.actor` wiring for Recording Studio events
- Root workspace plus seeded folder, page, and press kit recordables
- Recording Studio default layout, FlatPack assets, and Tailwind source scanning
- Mounted `RecordingStudio::Engine` route behavior inside a host app
- Dummy-only `/docs/*` pages for gem-specific onboarding

## Quick Start

```bash
cd test/dummy
bundle install
bin/rails db:setup
bin/dev
```

Run the commands above from the dummy app directory, not the repository root.

Then open the app and sign in with:

- Email: `admin@admin.com`
- Password: `Password`

## Useful Routes

- `/` - dummy app home page and template guidance
- `/recording_studio` - redirects to `/` while the mounted Recording Studio engine stays available under that prefix for non-root routes
- `/users/sign_in` - Devise sign-in page
- `/docs/install`, `/docs/config`, `/docs/recordable_types`, `/docs/recordings_tree`, `/docs/gem_views`, `/docs/methods` - dummy-only starter pages
- `/press_kits` - press kit list with a workspace chat. The chat column is one quarter on a wide screen, and it sticks to the top while the list scrolls. On a narrow screen the kit list comes first and the chat follows. Flatpack Grid is equal columns and SidebarLayout is the app shell, so that split stays a Tailwind grid. The top bar keeps Press kits, Agent chat, the workspace switcher, and Sign out on a wide screen. On a narrow screen those three links sit in Menu, next to the switcher. Each kit name sits above its description, and the description shows three lines. Sign out, on both widths, submits the same delete form.
- `/press_kits/:id` - one press kit with a chat scoped to that kit. Photos use Attachable's delivery URL. On a wide screen the gallery fills the column and stays within 28rem tall. The copy is heading, paragraph, and quote blocks, and a paragraph keeps its line breaks. An MCP edit to `content` rebuilds those blocks from the new text (a blank line starts a paragraph, and a leading “ is a quote) so the page shows the edit after a reload. Setting `sections` in the same save keeps the blocks you sent. A later edit that only changes the description keeps the sections already stored. A kit opts into Accessible so a grant can sit on that kit. The list shows kits the person can view. A kit in this workspace they cannot view is 403. A kit in another workspace is 404. `slug` repeats across workspaces, so it is not unique on the table. Reseeding fills a blank photo name or alt and leaves an in-app edit alone.
- `/agent-chat` and `/agent-chat/page` - workspace chat and the Press kit page chat
- `/up` - Rails health check

## Why This App Exists

Use this app to verify the generated addon experience before renaming the gem or copying patterns into another host app. If a layout, route, asset source, or Recording Studio initializer change breaks here, the template likely needs adjustment before reuse.

Authenticated pages use Recording Studio's shared default layout. Devise sign-in keeps `layouts/application`. Replace dummy docs page content so it matches the gem's actual concepts.

The home page in `app/views/home/index.html.erb` should stay a minimal demo surface for the gem's core feature. Do not turn it into a wall of documentation; the dummy docs pages exist so deeper explanations can live in focused sections.
