# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module InstructionsText
      private

      def instructions
        resolved_instructions
      end

      def resolved_instructions
        return @resolved_instructions if defined?(@resolved_instructions)

        @resolved_instructions = build_instructions
      end

      def build_instructions
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
        raise InstructionsError, length_message if over_limit?(text)

        text
      end

      def accept_override!
        gate = configuration.instructions_override
        raise InstructionsError, "instructions overrides are disabled" if gate == :none

        ensure_access!(@root_recording, role: gate)
      end

      def length_message
        "instructions must be at most #{configuration.max_instructions_length} characters"
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
