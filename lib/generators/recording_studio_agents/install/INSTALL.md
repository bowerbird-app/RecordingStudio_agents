RecordingStudioAgents install complete.

Next steps:

1. Review config/initializers/recording_studio_agents.rb.
2. Install engine migrations with `bin/rails generate recording_studio_agents:migrations`.
3. Apply the migrations with `bin/rails db:migrate`.
4. Configure Recording Studio AI with AccessibleAuthorization. Agents does not add a second authorization handler.
5. Register skills, knowledge, skill packs, and agents, then call Agent#run from a controller or job. Required skills always compile. Pass pack: or extra_skills: only when a ticket needs optional skills. Show coarse steps with Progress.for(run).
6. Mount Recording Studio Admin and enable the agents section.
7. Pin Recording Studio Admin Stimulus controllers in `config/importmap.rb` so Admin screen tables load.
8. Keep auth, layout, and current actor integration aligned with the host app.
