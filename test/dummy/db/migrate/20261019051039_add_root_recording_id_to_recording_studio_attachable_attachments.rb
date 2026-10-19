# frozen_string_literal: true

class AddRootRecordingIdToRecordingStudioAttachableAttachments < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_rs_attachable_attachments_on_root_recording_id"
  EVENT_RECORDABLE_SOURCE = <<~SQL.squish.freeze
    SELECT events.recordable_id AS attachment_id,
           recordings.root_recording_id,
           2 AS source_rank
    FROM recording_studio_events events
    INNER JOIN recording_studio_recordings recordings
      ON recordings.id = events.recording_id
    WHERE events.recordable_type = 'RecordingStudioAttachable::Attachment'
      AND events.recordable_id IS NOT NULL
      AND recordings.root_recording_id IS NOT NULL
  SQL
  RECORDING_SOURCE = <<~SQL.squish.freeze
    SELECT recordings.recordable_id AS attachment_id,
           recordings.root_recording_id,
           1 AS source_rank
    FROM recording_studio_recordings recordings
    WHERE recordings.recordable_type = 'RecordingStudioAttachable::Attachment'
      AND recordings.recordable_id IS NOT NULL
      AND recordings.root_recording_id IS NOT NULL
  SQL
  EVENT_PREVIOUS_SOURCE = <<~SQL.squish.freeze
    SELECT events.previous_recordable_id AS attachment_id,
           recordings.root_recording_id,
           3 AS source_rank
    FROM recording_studio_events events
    INNER JOIN recording_studio_recordings recordings
      ON recordings.id = events.recording_id
    WHERE events.previous_recordable_type = 'RecordingStudioAttachable::Attachment'
      AND events.previous_recordable_id IS NOT NULL
      AND recordings.root_recording_id IS NOT NULL
  SQL

  def up
    unless column_exists?(:recording_studio_attachable_attachments, :root_recording_id)
      add_column :recording_studio_attachable_attachments, :root_recording_id, :uuid
    end

    unless index_exists?(:recording_studio_attachable_attachments, :root_recording_id, name: INDEX_NAME)
      add_index :recording_studio_attachable_attachments, :root_recording_id, name: INDEX_NAME
    end

    backfill_root_recording_ids
  end

  def down
    if index_exists?(:recording_studio_attachable_attachments, :root_recording_id, name: INDEX_NAME)
      remove_index :recording_studio_attachable_attachments, name: INDEX_NAME
    end

    return unless column_exists?(:recording_studio_attachable_attachments, :root_recording_id)

    remove_column :recording_studio_attachable_attachments, :root_recording_id
  end

  def backfill_root_recording_ids
    return unless backfill_ready?

    chosen_root_ids.each { |attachment_id, root_id| stamp_root_recording_id(attachment_id, root_id) }
  end

  private

  def chosen_root_ids
    picks = {}
    connection.select_all(candidates_sql).each { |row| keep_better_candidate(picks, row) }
    picks.filter_map do |attachment_id, pick|
      root_id = pick[:root_recording_id]
      [attachment_id, root_id] if root_id.present?
    end
  end

  def keep_better_candidate(picks, row)
    attachment_id = row["attachment_id"]
    rank = row["source_rank"].to_i
    current = picks[attachment_id]
    return if current && current.fetch(:rank) <= rank

    picks[attachment_id] = { rank: rank, root_recording_id: row["root_recording_id"] }
  end

  def stamp_root_recording_id(attachment_id, root_id)
    execute(<<~SQL.squish)
      UPDATE recording_studio_attachable_attachments
      SET root_recording_id = #{connection.quote(root_id)}
      WHERE id = #{connection.quote(attachment_id)}
        AND root_recording_id IS NULL
    SQL
  end

  def candidates_sql
    "SELECT attachment_id, root_recording_id, source_rank FROM (#{recording_sources} #{event_sources}) candidates"
  end

  def recording_sources
    RECORDING_SOURCE
  end

  def event_sources
    return "" unless table_exists?(:recording_studio_events)

    "UNION ALL #{EVENT_RECORDABLE_SOURCE} UNION ALL #{EVENT_PREVIOUS_SOURCE}"
  end

  def backfill_ready?
    table_exists?(:recording_studio_attachable_attachments) &&
      column_exists?(:recording_studio_attachable_attachments, :root_recording_id) &&
      table_exists?(:recording_studio_recordings)
  end
end
