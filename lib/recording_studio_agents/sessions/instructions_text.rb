# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module InstructionsText
      private

      def instructions
        override = stripped_override
        return host_instructions if override.nil?

        accept_override!
        composed_instructions(override)
      end

      def stripped_override
        return if @instructions.nil?
        raise InstructionsError, "instructions must be a string" unless @instructions.is_a?(String)

        text = @instructions.strip
        return if text.empty?
        raise InstructionsError, "instructions is too long" if over_limit?(text)

        text
      end

      def accept_override!
        gate = configuration.instructions_override
        raise InstructionsError, "instructions overrides are disabled" if gate == :none
        return if override_allowed?(gate)

        raise AccessDeniedError, "actor cannot override instructions"
      end

      def override_allowed?(gate)
        RecordingStudioAccessible.authorized?(actor: @actor, recording: @root_recording, role: gate)
      end

      def composed_instructions(override)
        host = host_instructions.to_s.strip
        return override if host.empty?

        "#{host}\n\n#{override}"
      end

      def host_instructions
        configuration.instructions
      end

      def over_limit?(text)
        text.length > configuration.max_instructions_length
      end
    end
  end
end
