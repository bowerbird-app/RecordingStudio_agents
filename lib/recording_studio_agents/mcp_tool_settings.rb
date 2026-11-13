# frozen_string_literal: true

module RecordingStudioAgents
  # Name lists and the per-turn write cap for in-process chat tools.
  module McpToolSettings
    attr_reader :mcp_max_writes_per_turn, :mcp_tool_allow, :mcp_tool_deny, :allow_chat_tools_in_transaction,
                :chat_tool_stale_after, :chat_tool_deadline

    def mcp_max_writes_per_turn=(value)
      @mcp_max_writes_per_turn = strict_positive_integer(value)
    end

    def mcp_tool_allow=(value)
      @mcp_tool_allow = tool_name_list(value, "mcp_tool_allow")
    end

    def mcp_tool_deny=(value)
      @mcp_tool_deny = tool_name_list(value, "mcp_tool_deny")
    end

    def allow_chat_tools_in_transaction=(value)
      raise Error, "allow_chat_tools_in_transaction must be true or false" unless [true, false].include?(value)

      @allow_chat_tools_in_transaction = value
    end

    def chat_tool_stale_after=(value)
      duration = positive_duration(value, "chat_tool_stale_after")
      raise Error, "chat_tool_stale_after must be longer than chat_tool_deadline" unless duration > chat_tool_deadline

      @chat_tool_stale_after = duration
    end

    def chat_tool_deadline=(value)
      duration = positive_duration(value, "chat_tool_deadline")
      unless duration < chat_tool_stale_after
        raise Error, "chat_tool_deadline must be shorter than chat_tool_stale_after"
      end

      @chat_tool_deadline = duration
    end

    private

    def mcp_limits
      {
        mcp_max_writes_per_turn: mcp_max_writes_per_turn,
        mcp_tool_allow: mcp_tool_allow, mcp_tool_deny: mcp_tool_deny,
        allow_chat_tools_in_transaction: allow_chat_tools_in_transaction,
        chat_tool_stale_after: chat_tool_stale_after, chat_tool_deadline: chat_tool_deadline
      }
    end

    def strict_positive_integer(value)
      count = Integer(value)
      whole = value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A[+]?\d+\z/))
      raise ArgumentError unless whole && count >= 1

      count
    rescue ArgumentError, TypeError
      raise Error, "mcp_max_writes_per_turn must be a positive integer"
    end

    def assign_tool_defaults
      @mcp_max_writes_per_turn = 3
      @mcp_tool_allow = nil
      @mcp_tool_deny = nil
      @allow_chat_tools_in_transaction = false
      @chat_tool_deadline = 2.minutes
      @chat_tool_stale_after = 10.minutes
    end

    def positive_duration(value, name)
      duration = value if value.is_a?(ActiveSupport::Duration)
      duration = value.seconds if value.is_a?(Numeric) && value.positive?
      raise Error, "#{name} must be a positive duration" if duration.nil? || duration <= 0

      duration
    end

    def tool_name_list(value, name)
      return if value.nil?
      raise Error, "#{name} must be an array of tool names" unless value.is_a?(Array)

      value.map { |entry| tool_name(entry, name) }.uniq
    end

    def tool_name(entry, label)
      text = entry.to_s if entry.is_a?(String) || entry.is_a?(Symbol)
      return text if text&.match?(RecordingStudioAI::Agents::ToolCall::NAME_PATTERN)

      raise Error, "#{label} must be an array of tool names"
    end
  end
end
