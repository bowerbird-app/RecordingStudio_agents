class AgentChatsController < ApplicationController
  def show
    ensure_demo_access
    ensure_sample_chats
  end

  def page
    ensure_demo_access
    @page_recording = find_or_create_page
    ensure_sample_chats
  end

  private

  def ensure_demo_access
    root = current_root
    return if root.blank?
    return if RecordingStudioAccessible.authorized?(actor: current_user, recording: root, role: :edit)

    RecordingStudioAccessible::AccessCreationContext.allow do
      root.record(RecordingStudio::Access, actor: current_user, parent_recording: root) do |access|
        access.actor = current_user
        access.role = "edit"
      end
    end
  end

  def find_or_create_page
    root = current_root
    return if root.blank?

    existing = page_recordings(root).find { |recording| recording.recordable.title == "Press kit" }
    return existing if existing

    root.record(Page, actor: current_user, parent_recording: root) do |page|
      page.title = "Press kit"
    end
  end

  def ensure_sample_chats
    return if Rails.env.test?

    root = current_root
    return if root.blank?

    page = @page_recording || find_or_create_page
    return if page.blank?

    ensure_chat(root, root, "Workspace welcome")
    ensure_chat(root, root, "All-hands notes")
    ensure_chat(root, page, "Press kit draft")
  end

  def ensure_chat(root, parent, title)
    return if chat_titled(root, parent, title)

    root.record(RecordingStudioAgents::Session, actor: current_user, parent_recording: parent) do |chat|
      chat.title = title
      chat.status = "active"
      chat.model = "gpt-6-astra"
      chat.purpose = "agent_chat"
      chat.instructions = RecordingStudioAgents.configuration.instructions
    end
  end

  def chat_titled(root, parent, title)
    RecordingStudio::Recording.for_root(root.id).where(
      parent_recording_id: parent.id, recordable_type: RecordingStudioAgents::Session.name
    ).find { |recording| recording.recordable.title == title }
  end

  def page_recordings(root)
    RecordingStudio::Recording.for_root(root.id).where(recordable_type: "Page")
  end

  def current_root
    RecordingStudioAgents.configuration.request_root.call(self)
  end
end
