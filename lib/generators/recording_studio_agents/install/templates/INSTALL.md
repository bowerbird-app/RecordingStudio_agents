RecordingStudioAgents install complete.

Next steps:

1. Review config/initializers/recording_studio_agents.rb and set any required options.
2. If you use environment-specific settings, create config/recording_studio_agents.yml.
3. Install the engine migrations with `bin/rails generate recording_studio_agents:migrations`. That includes `recording_studio_agents_chat_tool_audits`, one row per in-process chat tool call. The row stores argument keys, never values.
4. Install Logs run tables (if the host does not already have them) and addon migrations, in this order:

```bash
bin/rails generate recording_studio_logs:migrations
bin/rails recording_studio_ai:install:migrations
bin/rails db:migrate
```
5. Run `bin/rails tailwindcss:build` if you use Tailwind CSS.
6. Mount routes are added at the configured mount path. Adjust auth, layout, and current actor integration to match your host app.
7. Keep strict recordable declarations enabled and add `recording_studio_recordable(...)` to every configured recordable before running `RecordingStudio.validate_recordable_declarations!`.