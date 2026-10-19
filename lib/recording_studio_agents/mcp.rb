# frozen_string_literal: true

require "recording_studio_agents/mcp/contracts"
require "recording_studio_agents/mcp/context"
require "recording_studio_agents/mcp/chats"
require "recording_studio_agents/mcp/items"
require "recording_studio_agents/mcp/registration"

module RecordingStudioAgents
  module Mcp
    module_function

    def register!
      Registration.register!
    end
  end
end
