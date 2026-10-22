# frozen_string_literal: true

# Refresh an open press kit when its recording changes.
#
# recordings.event_created fires inside the record! transaction. Wait for
# commit, then refresh the recording stream. A rollback sends nothing.
# revise inserts a new PressKit row, so this targets the recording, not the
# recordable. broadcasts_refreshes on PressKit would miss the open page.

if defined?(Turbo::StreamsChannel)
  press_kit_refresh_actions = %w[updated trashed restored].freeze

  ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
    payload = ActiveSupport::Notifications::Event.new(*args).payload
    next unless payload[:recordable_type] == "PressKit"
    next unless press_kit_refresh_actions.include?(payload[:action].to_s)

    recording_id = payload[:recording_id]
    ActiveRecord.after_all_transactions_commit do
      recording = RecordingStudio::Recording.find_by(id: recording_id)
      next if recording.nil?

      Turbo::StreamsChannel.broadcast_refresh_later_to(recording)
    end
  end
end
