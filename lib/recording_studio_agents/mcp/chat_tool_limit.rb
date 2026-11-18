# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # Shares the Recording Studio API read and write windows. A signed-in person
    # with no API credential is counted as that actor. Redis errors fail closed.
    module ChatToolLimit
      module_function

      def limited?(turn_tools, name, actor)
        return false unless defined?(RecordingStudioApi::RateLimit)

        grant = turn_tools.grant
        return false unless RecordingStudioApi::ApiRuntimePolicy.for(ChatToolCall.api_key(grant)).rate_limit_api_enabled

        decision = RecordingStudioApi::RateLimit.check(
          kind: rate_bucket(turn_tools, name), identifier: identifier_for(grant, actor),
          api: ChatToolCall.api_key(grant), fail_closed: true
        )
        decision&.limited? || false
      end

      def rate_bucket(turn_tools, name)
        turn_tools.read_only?(name) ? "api_read" : "api_write"
      end

      def identifier_for(grant, actor)
        return "credential:#{grant.credential.id}" if grant.credential&.id
        return "client:#{grant.api_client.id}" if grant.api_client&.id

        "actor:#{actor.class.name}:#{actor.id}"
      end
    end
  end
end
