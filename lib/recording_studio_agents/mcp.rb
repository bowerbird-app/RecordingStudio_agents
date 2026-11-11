# frozen_string_literal: true

require "recording_studio_agents/mcp/contracts"
require "recording_studio_agents/mcp/context"
require "recording_studio_agents/mcp/chats"
require "recording_studio_agents/mcp/items"
require "recording_studio_agents/mcp/response_schemas"
require "recording_studio_agents/mcp/registration"
require "recording_studio_agents/mcp/chat_tools"
require "recording_studio_agents/mcp/chat_tool_call"
require "recording_studio_agents/mcp/chat_tool_limit"
require "recording_studio_agents/mcp/chat_tool_log"

module RecordingStudioAgents
  module Mcp
    module_function

    def register!
      Registration.register!
    end
  end
end
