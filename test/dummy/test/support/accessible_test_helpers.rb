# frozen_string_literal: true

module AccessibleTestHelpers
  ROLE_RANK = {
    "view" => 1,
    "edit" => 2,
    "admin" => 3
  }.freeze

  def grant_accessible!(recording:, actor:, role: :admin)
    current_role = RecordingStudioAccessible.role_for(actor: actor, recording: recording)
    return if role_covers?(current_role, role)

    if role.to_sym == :admin
      bootstrap_result = RecordingStudioAccessible.bootstrap_owner_access!(
        recording: recording,
        actor: actor
      )
      return if bootstrap_result.success?
    end

    previous = RecordingStudioAccessible.configuration.access_management_authorizer
    begin
      RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
      result = RecordingStudioAccessible.grant_access(
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: actor
      )
      raise result.error unless result.success?
    ensure
      RecordingStudioAccessible.configuration.access_management_authorizer = previous
    end
  end

  def switch_to_root!(root_recording, return_to: "/")
    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: root_recording.id,
        return_to: return_to
      }
    }
  end

  private

  def role_covers?(current_role, required_role)
    return false if current_role.nil?

    (ROLE_RANK[current_role.to_s] || 0) >= (ROLE_RANK[required_role.to_s] || 0)
  end
end
