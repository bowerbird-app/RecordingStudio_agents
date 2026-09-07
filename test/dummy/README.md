# Dummy host

This Rails app exists to prove Recording Studio Agents in a real host.

## What it covers

- Devise authentication with a seeded admin user (`admin@admin.com` / `Password`)
- Workspace, Folder, and Page with Accessible grants
- An Admin root for Recording Studio Admin
- Page librarian demo on `/` (`POST /agents/demo`)
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

- `/` - page librarian demo
- `/users/sign_in` - Devise sign-in
- `/admin` - Agents admin section
- `/recording_studio` - redirects to `/`
- `/up` - health check

Authenticated pages use Recording Studio's shared default layout. Devise sign-in keeps `layouts/application`.
