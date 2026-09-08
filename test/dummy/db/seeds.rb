find_or_record_child = lambda do |recordable, root_recording, parent_recording|
  RecordingStudio::Recording.find_by(
    root_recording: root_recording,
    parent_recording: parent_recording,
    recordable: recordable,
    trashed_at: nil
  ) || RecordingStudio.record!(
    action: "created",
    recordable: recordable,
    root_recording: root_recording,
    parent_recording: parent_recording
  ).recording
end

bootstrap_owner_access = lambda do |recording, actor|
  current_role = RecordingStudioAccessible.role_for(actor: actor, recording: recording)
  next if current_role == :admin

  result = RecordingStudioAccessible.bootstrap_owner_access!(
    recording: recording,
    actor: actor
  )
  next if result.success?

  grant_workspace_access.call(recording, actor)
end

grant_workspace_access = lambda do |recording, actor|
  current_role = RecordingStudioAccessible.role_for(actor: actor, recording: recording)
  next if current_role == :admin

  original = RecordingStudioAccessible.configuration.access_management_authorizer
  begin
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: :admin,
      manager_actor: actor
    )
    raise "Failed to grant workspace access: #{result.error}" if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end

user = User.find_or_create_by!(email: "admin@admin.com") do |record|
  record.password = "Password"
  record.password_confirmation = "Password"
end

workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
accessible_workspace = Workspace.find_or_create_by!(name: "Client Workspace")
private_workspace = Workspace.find_or_create_by!(name: "Private Workspace")
folder = Folder.find_or_create_by!(name: "Product Docs")
page = Page.find_or_create_by!(title: "Getting Started")

previous_actor = Current.actor
Current.actor = user

begin
  root_recording = RecordingStudio.root_recording_for(workspace)
  accessible_root_recording = RecordingStudio.root_recording_for(accessible_workspace)
  private_root_recording = RecordingStudio.root_recording_for(private_workspace)

  folder_recording = find_or_record_child.call(folder, root_recording, root_recording)
  find_or_record_child.call(page, root_recording, folder_recording)

  admin_root = AdminRoot.find_or_create_by!(name: "Admin")
  admin_root_recording = RecordingStudio.root_recording_for(admin_root)
  bootstrap_owner_access.call(admin_root_recording, user)

  [root_recording, accessible_root_recording, private_root_recording].each do |recording|
    grant_workspace_access.call(recording, user)
  end

  unless RecordingStudioAgents::AgentRun.exists?(idempotency_key: "seed:page_librarian")
    task = RecordingStudioAgents::Task.create!(
      root_recording_id: root_recording.id,
      context_recording_id: nil,
      task_key: "seed:find_page",
      goal: "Find the Getting Started page.",
      input_digest: "seed"
    )
    RecordingStudioAgents::AgentRun.create!(
      task: task,
      root_recording_id: root_recording.id,
      agent_key: "page_librarian",
      agent_version: 1,
      program_digest: "seed",
      idempotency_key: "seed:page_librarian",
      status: "failed",
      initiator_type: "User",
      initiator_id: user.id,
      initiator_kind: "user",
      execution_source: "console",
      failure_category: "provider_unavailable",
      failure_code: "seed",
      failure_message: "Seeded failed run",
      failure_retryable: true,
      completed_at: Time.current
    )
  end

  unless RecordingStudioAgents::AgentRun.exists?(idempotency_key: "seed:page_librarian_ok")
    task = RecordingStudioAgents::Task.find_or_create_by!(
      root_recording_id: root_recording.id,
      task_key: "seed:find_page"
    ) do |record|
      record.goal = "Find the Getting Started page."
      record.input_digest = "seed"
    end
    now = Time.current
    ai_run = RecordingStudioAI::Run.create!(
      operation: "generation",
      purpose: "agent_page_librarian",
      status: "completed",
      root_recording_id: root_recording.id,
      initiator_type: "User",
      initiator_id: user.id.to_s,
      initiator_kind: "user",
      execution_source: "console",
      request_id: "recording-studio-agents:seed-success",
      started_at: now,
      completed_at: now,
      total_tokens: 12_000,
      input_tokens: 9_600,
      output_tokens: 2_400,
      custom_tool_invocation_count: 4,
      latency_ms: 1_800
    )
    RecordingStudioAgents::AgentRun.create!(
      task: task,
      root_recording_id: root_recording.id,
      agent_key: "page_librarian",
      agent_version: 1,
      program_digest: "seed-ok",
      idempotency_key: "seed:page_librarian_ok",
      status: "succeeded",
      recording_studio_ai_run_id: ai_run.id,
      initiator_type: "User",
      initiator_id: user.id,
      initiator_kind: "user",
      execution_source: "console",
      completed_at: now
    )
  end
ensure
  Current.actor = previous_actor
end
