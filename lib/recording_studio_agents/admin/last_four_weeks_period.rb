# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    # Admin Period treats last_4_weeks as four 7-day jumps (today minus 28).
    # Flatpack labels Last 4 weeks when the window is today minus 27 through today.
    module LastFourWeeksPeriod
      def from_preset_key(key, reference_date: Date.current)
        return super unless key.to_s == "last_4_weeks"

        RecordingStudioAdmin::Period.new(
          amount: 4,
          unit: :week,
          start_date: reference_date - 27.days,
          end_date: reference_date,
          preset_key: :last_4_weeks
        )
      end
    end
  end
end
