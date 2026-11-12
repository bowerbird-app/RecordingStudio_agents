RecordingStudioAgents install complete.

Next steps:

1. Review config/initializers/recording_studio_agents.rb and set any required options.
2. If you use environment-specific settings, create config/recording_studio_agents.yml.
3. Install the engine migrations with `bin/rails generate recording_studio_agents:migrations`.
4. Install Recording Studio AI migrations with `bin/rails railties:install:migrations FROM=recording_studio_ai`. A new chat writes a run before it calls the provider, and this gem does not create `recording_studio_ai_runs`.
5. Apply the migrations with `bin/rails db:migrate`.
6. Run `bin/rails tailwindcss:build` if you use Tailwind CSS.
7. Mount routes are added at the configured mount path. Adjust auth, layout, and current actor integration to match your host app.
8. Keep strict recordable declarations enabled and add `recording_studio_recordable(...)` to every configured recordable before running `RecordingStudio.validate_recordable_declarations!`.