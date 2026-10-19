# frozen_string_literal: true

require "recording_studio"
require "recording_studio_ai"
require "recording_studio_agents/version"

module RecordingStudioAgents
  class Error < StandardError; end
  class IsolationError < Error; end

  module Sessions
    class AccessDeniedError < Error; end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end
  end
end

require "recording_studio_agents/engine"
require "recording_studio_agents/configuration"
require "recording_studio_agents/capabilities/example"
require "recording_studio/capabilities/agents"
require "recording_studio_agents/provider_sessions"
require "recording_studio_agents/sessions/root_guard"
require "recording_studio_agents/sessions/global_key"
require "recording_studio_agents/sessions/access"
require "recording_studio_agents/sessions/chat_lookup"
require "recording_studio_agents/sessions/chat_draft"
require "recording_studio_agents/sessions/create"
require "recording_studio_agents/sessions/append"
require "recording_studio_agents/sessions/rename"
require "recording_studio_agents/sessions/close"
require "recording_studio_agents/sessions/expire"
require "recording_studio_agents/mcp"

require "recording_studio_agents/chatkit/protocol_error"
require "recording_studio_agents/chatkit/payload"
require "recording_studio_agents/chatkit/assistant_turn"
require "recording_studio_agents/chatkit/model_stream"
require "recording_studio_agents/chatkit/turn"
require "recording_studio_agents/chatkit/catalog"
require "recording_studio_agents/chatkit/server"
require "recording_studio_agents/chatkit/readiness"
require "recording_studio_agents/chatkit_helper"
