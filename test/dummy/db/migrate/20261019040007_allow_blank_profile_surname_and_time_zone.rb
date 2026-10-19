# frozen_string_literal: true

class AllowBlankProfileSurnameAndTimeZone < ActiveRecord::Migration[8.1]
  def change
    change_column_null :recording_studio_user_profiles, :last_name, true
    change_column_null :recording_studio_user_profiles, :time_zone, true
  end
end
