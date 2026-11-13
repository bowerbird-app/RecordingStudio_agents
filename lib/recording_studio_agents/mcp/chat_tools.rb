# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # Function tools for one ChatKit turn. Definitions go out at session create.
    # Each call runs in process as the actor's own Accessible grant.
    module ChatTools
      # The tools this gem registers call back into a chat. Sending them would let
      # the model open another turn while this one is still running.
      MODES = %i[write read off].freeze

      module_function

      def definitions(actor:, root:)
        return if off? || !installed?

        grant = grant_for(actor, root)
        return if grant.nil?

        surface = RecordingStudioMcp::ToolSurface.for(access_grant: grant)
        listed = surface.tool_definitions.filter_map { |definition| function_tool(surface, definition) }
        listed.presence
      end

      def answer(call, actor:, root:)
        { call_id: call.call_id, turn_id: call.provider_turn_id }.merge(result_body(call, actor, root))
      end

      def invoke(name, arguments, actor:, root:, call_id:)
        ChatToolCall.perform(name, arguments, actor: actor, root: root, call_id: call_id)
      end

      def result_body(call, actor, root)
        return argument_failure(call, actor, root) if call.arguments_error.present?

        ChatToolCall.outcome(invoke(call.name, call.arguments, actor: actor, root: root, call_id: call.call_id))
      end

      def argument_failure(call, actor, root)
        note_call(call, actor, root, "error")
        { error: ChatToolCall.bounded(call.arguments_error) }
      end

      def note_call(call, actor, root, outcome)
        reserved = ChatToolAudit.current_reserved
        return ChatToolAudit.finish!(reserved, outcome) if reserved

        ChatToolAudit.record!(
          ChatToolAudit::Entry.new(name: call.name, arguments: nil, call_id: call.call_id),
          actor: actor, kind: kind_for(call.name, grant_for(actor, root)), outcome: outcome
        )
      end

      def installed?
        defined?(RecordingStudioMcp) && defined?(RecordingStudioApi)
      end

      def off?
        mode == :off
      end

      def mode
        value = RecordingStudioAgents.configuration.mcp_tools
        MODES.include?(value) ? value : :write
      end

      def kind_for(name, grant)
        return "write" if grant.nil?

        read = RecordingStudioMcp::ToolSurface.for(access_grant: grant).read_only_tool?(name)
        read ? "read" : "write"
      end

      def named_tool?(name)
        return false if denied?(name)

        allow = RecordingStudioAgents.configuration.mcp_tool_allow
        allow.nil? || allow.include?(name.to_s)
      end

      def denied?(name)
        Array(RecordingStudioAgents.configuration.mcp_tool_deny).include?(name.to_s)
      end

      def self_tool?(name)
        Registration.own_tool?(name)
      end

      def grant_for(actor, root)
        return if actor.nil? || root.nil?
        return unless defined?(RecordingStudioApi) && defined?(RecordingStudioAccessible)

        access_recording = access_recording_for(actor, root)
        return if access_recording.nil?

        RecordingStudioApi::AccessGrant.new(
          api_client: nil, credential: nil, access_recording: access_recording,
          root_recording: root, authorized_by: actor
        )
      end

      def access_recording_for(actor, root)
        relation = RecordingStudioAccessible.access_recordings_for_actor(recording: root, actor: actor)
        return if relation.blank?

        relation.detect { |recording| recording.parent_recording_id == root.id } || relation.first
      end

      def function_tool(surface, definition)
        name = field(definition, :name).to_s
        return unless listed_name?(surface, name)

        description = field(definition, :description).to_s.strip
        parameters = json_object(field(definition, :inputSchema))
        return if description.empty? || parameters.nil?

        { type: "function", name: name, description: description, parameters: parameters }
      end

      def listed_name?(surface, name)
        return false if self_tool?(name) || !usable_name?(name) || !named_tool?(name)
        return false if mode == :read && !surface.read_only_tool?(name)

        true
      end

      def usable_name?(name)
        name.match?(RecordingStudioAI::Agents::ToolCall::NAME_PATTERN)
      end

      def field(definition, key)
        definition[key] || definition[key.to_s]
      end

      def json_object(schema)
        return unless schema.is_a?(Hash)

        parsed = JSON.parse(JSON.generate(schema))
        parsed if parsed.is_a?(Hash) && parsed["type"] == "object"
      rescue JSON::GeneratorError, JSON::ParserError
        nil
      end
    end
  end
end
