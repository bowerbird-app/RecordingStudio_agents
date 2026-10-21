# frozen_string_literal: true

module RecordingStudioAgents
  module ScopedParent
    QUERY_PARAM = "page_recording_id"
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    module_function

    def resolve!(id, root:, actor: nil, access_grant: nil)
      text = id.is_a?(String) ? id.strip : ""
      return if text.empty?

      recording = find(text)
      missing!(recording, root)
      authorize!(recording, actor, access_grant)
      recording
    end

    def find(id)
      return unless id.match?(UUID)

      RecordingStudio::Recording.find_by(id: id)
    end

    def missing!(recording, root)
      return if recording&.root_recording_id.present? && recording.root_recording_id == root.id

      raise ChatKit::ProtocolError.new("page was not found", status: 404)
    end

    def authorize!(recording, actor, access_grant)
      if access_grant
        access_grant.authorize!(recording: recording, role: :view)
        return
      end

      return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)

      raise ChatKit::ProtocolError.new("actor cannot access this recording", status: 403)
    end
  end
end
