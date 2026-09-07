RecordingStudioAgents install complete.

Next steps:

1. Review config/initializers/recording_studio_agents.rb.
2. Install engine migrations with `bin/rails generate recording_studio_agents:migrations`.
3. Apply the migrations with `bin/rails db:migrate`.
4. Configure Recording Studio AI with AccessibleAuthorization. Agents does not add a second authorization handler.
5. Register skills, knowledge, and agents, then call Agent#run from a controller or job.
6. Mount Recording Studio Admin and enable the agents section.
7. Keep auth, layout, and current actor integration aligned with the host app.
