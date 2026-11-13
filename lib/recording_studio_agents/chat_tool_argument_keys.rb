# frozen_string_literal: true

module RecordingStudioAgents
  # Names stored on a chat tool audit. Values never get here.
  module ChatToolArgumentKeys
    MAX_KEYS = 50
    MAX_LENGTH = 64
    PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    module_function

    def list(arguments)
      return [] unless arguments.is_a?(Hash)

      kept = []
      arguments.each_key do |key|
        break if kept.size >= MAX_KEYS

        name = clean(key)
        kept << name if name && !kept.include?(name)
      end
      kept
    end

    def clean(key)
      text = key.to_s[0, MAX_LENGTH]
      text if text&.match?(PATTERN)
    end
  end
end
