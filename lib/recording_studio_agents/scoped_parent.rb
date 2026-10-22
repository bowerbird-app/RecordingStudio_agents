# frozen_string_literal: true

module RecordingStudioAgents
  module ScopedParent
    QUERY_PARAM = "page_recording_id"
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    module_function

    def resolve!(id, root:, actor: nil, access_grant: nil)
      return if absent?(id)

      recording = find(id)
      missing!(recording, root)
      authorize!(recording, actor, access_grant)
      eligible!(recording)
      recording
    end

    def absent?(id)
      id.nil? || (id.is_a?(String) && id.strip.empty?)
    end

    def find(id)
      return unless id.is_a?(String)

      text = id.strip
      return unless text.match?(UUID)

      RecordingStudio::Recording.find_by(id: text)
    end

    def missing!(recording, root)
      return if kept_in_root?(recording, root)

      raise ChatKit::ProtocolError.new("page was not found", status: 404)
    end

    def kept_in_root?(recording, root)
      recording&.root_recording_id.present? && recording.root_recording_id == root.id && kept?(recording)
    end

    def kept?(recording)
      return true unless recording.respond_to?(:trashed_at)

      recording.trashed_at.blank?
    end

    def authorize!(recording, actor, access_grant)
      if access_grant
        access_grant.authorize!(recording: recording, role: :view)
        return
      end

      return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)

      raise ChatKit::ProtocolError.new("actor cannot access this recording", status: 403)
    end

    def eligible!(recording)
      return if RecordingStudio.parent_allowed?(child_type: Session, parent_recording: recording)

      raise ChatKit::ProtocolError.new("page cannot hold a chat", status: 422)
    end
  end
end
