# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    # Flatpack labels Last 4 weeks when the window is today minus 27 through today.
    # Admin Period still treats last_4_weeks as four 7-day jumps (today minus 28).
    # This gem keeps a Period prepend so Runs and Usage by agent show Last 4 weeks.
    # Do not copy this prepend in a host. It belongs in Admin or Flatpack when
    # those gems ship the 27-day window.
    module LastFourWeeks
      LOOKBACK_DAYS = 27

      module_function

      def current_range(now: Time.current)
        start_date = now.to_date - LOOKBACK_DAYS
        start_date.beginning_of_day..now
      end

      def previous_range(now: Time.current)
        current_start = now.to_date - LOOKBACK_DAYS
        span_days = LOOKBACK_DAYS + 1
        previous_start = current_start - span_days
        previous_end = current_start - 1
        previous_start.beginning_of_day..previous_end.end_of_day
      end
    end

    module LastFourWeeksPeriod
      def from_preset_key(key, reference_date: Date.current)
        return super unless key.to_s == "last_4_weeks"

        RecordingStudioAdmin::Period.new(
          amount: 4,
          unit: :week,
          start_date: reference_date - LastFourWeeks::LOOKBACK_DAYS,
          end_date: reference_date,
          preset_key: :last_4_weeks
        )
      end
    end
  end
end
