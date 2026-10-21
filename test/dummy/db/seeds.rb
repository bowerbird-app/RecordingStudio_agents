# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

find_or_record_child = lambda do |recordable, root_recording, parent_recording|
  RecordingStudio::Recording.where(RecordingStudio::Recording.recording_studio_trashable_kept_sql).find_by(
    root_recording: root_recording,
    parent_recording: parent_recording,
    recordable: recordable
  ) || RecordingStudio.record!(
    action: "created",
    recordable: recordable,
    root_recording: root_recording,
    parent_recording: parent_recording
  ).recording
end

# Create the admin user
user = User.find_or_create_by!(email: "admin@admin.com") do |u|
  u.password = "Password"
  u.password_confirmation = "Password"
end

# Create the workspace recordables
workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
accessible_workspace = Workspace.find_or_create_by!(name: "Client Workspace")
private_workspace = Workspace.find_or_create_by!(name: "Private Workspace")
folder = Folder.find_or_create_by!(name: "Product Docs")
page = Page.find_or_create_by!(title: "Getting Started")

previous_actor = Current.actor
Current.actor = user

begin
  # Create the root recording
  root_recording = RecordingStudio.root_recording_for(workspace)
  accessible_root_recording = RecordingStudio.root_recording_for(accessible_workspace)
  private_root_recording = RecordingStudio.root_recording_for(private_workspace)

  folder_recording = find_or_record_child.call(folder, root_recording, root_recording)

  find_or_record_child.call(page, root_recording, folder_recording)
ensure
  Current.actor = previous_actor
end

puts "Seeded: admin@admin.com / Password"
puts "Seeded: Workspace '#{workspace.name}' with root recording ##{root_recording.id}"
puts "Seeded: Workspace '#{accessible_workspace.name}' with root recording ##{accessible_root_recording.id}"
puts "Seeded: Workspace '#{private_workspace.name}' with root recording ##{private_root_recording.id}"
puts "Seeded: Folder '#{folder.name}' and page '#{page.title}'"

seed_demo_chats = lambda do |root_recording|
  return if root_recording.blank?
  return if RecordingStudioAccessible.authorized?(actor: user, recording: root_recording, role: :edit)

  RecordingStudioAccessible::AccessCreationContext.allow do
    root_recording.record(RecordingStudio::Access, actor: user, parent_recording: root_recording) do |access|
      access.actor = user
      access.role = "edit"
    end
  end
end

record_page = lambda do |root_recording, title|
  existing = RecordingStudio::Recording.for_root(root_recording.id).where(recordable_type: "Page").find do |recording|
    recording.recordable.title == title
  end
  next existing if existing

  root_recording.record(Page, actor: user, parent_recording: root_recording) do |page_record|
    page_record.title = title
  end
end

record_chat = lambda do |root_recording, parent_recording, title|
  existing = RecordingStudio::Recording.for_root(root_recording.id).where(
    parent_recording_id: parent_recording.id, recordable_type: RecordingStudioAgents::Session.name
  ).find { |recording| recording.recordable.title == title }
  next existing if existing

  root_recording.record(RecordingStudioAgents::Session, actor: user, parent_recording: parent_recording) do |chat|
    chat.title = title
    chat.status = "active"
    chat.model = "gpt-6-astra"
    chat.purpose = "agent_chat"
    chat.instructions = RecordingStudioAgents.configuration.instructions
  end
end

remember_line = lambda do |root_recording, chat, text|
  next if RecordingStudioAgents::Item.exists?(recording_id: chat.id)

  RecordingStudioAgents::Item.create!(
    id: SecureRandom.uuid, recording: chat, root_recording: root_recording,
    role: "user", text: text, status: "done"
  )
end

seed_press_kit = lambda do |demo_root, source_path|
  source = JSON.parse(File.read(source_path))
  slug = File.basename(source_path, ".json")
  recording = RecordingStudio::Recording.for_root(demo_root.id).where(recordable_type: "PressKit").find do |candidate|
    candidate.recordable.name == source.fetch("name")
  end
  recording ||= demo_root.record(PressKit, actor: user, parent_recording: demo_root) do |press_kit|
    press_kit.name = source.fetch("name")
    press_kit.description = source.fetch("description")
    press_kit.content = source.fetch("content")
  end

  attached_names = recording.images(per_page: 50).map { |image| image.recordable.original_filename }
  source.fetch("images").each do |image|
    filename = "#{slug}-#{image.fetch("file")}"
    next if attached_names.include?(filename)

    File.open(Rails.root.join("db/press_kit_images", slug, image.fetch("file")), "rb") do |io|
      result = RecordingStudioAttachable::Services::ImportAttachment.call(
        parent_recording: recording,
        io: io,
        filename: filename,
        content_type: "image/jpeg",
        actor: user,
        name: image.fetch("alt"),
        description: source.fetch("source")
      )
      raise result.error.to_s unless result.success?
    end
    attached_names << filename
  end
  recording
end

Current.actor = user
begin
  [root_recording, accessible_root_recording].each do |demo_root|
    seed_demo_chats.call(demo_root)
    press_kit = record_page.call(demo_root, "Press kit")
    record_chat.call(demo_root, demo_root, "Workspace welcome")
    record_chat.call(demo_root, demo_root, "All-hands notes")
    draft = record_chat.call(demo_root, press_kit, "Press kit draft")
    remember_line.call(demo_root, draft, "Draft the one-page brief.")
    Dir[Rails.root.join("db/press_kits/*.json")].sort.each do |source_path|
      seed_press_kit.call(demo_root, source_path)
    end
  end
ensure
  Current.actor = previous_actor
end

puts "Seeded: Press kit page chats"
