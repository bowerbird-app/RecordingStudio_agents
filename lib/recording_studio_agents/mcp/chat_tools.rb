# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # Function tools for one ChatKit turn. Definitions go out at session create.
    # Each call runs in process as the actor's own Accessible grant.
    module ChatTools
      # Chat and item tools call back into this gem. Sending them would let the
      # model open another turn while this one is still running.
      SELF_PREFIXES = %w[agent_chats_ agent_items_].freeze
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
        body = if call.arguments_error.present?
                 { error: ChatToolCall.bounded(call.arguments_error) }
               else
                 ran = invoke(call.name, call.arguments, actor: actor, root: root, call_id: call.call_id)
                 ChatToolCall.outcome(ran)
               end
        { call_id: call.call_id, turn_id: call.provider_turn_id }.merge(body)
      end

      def invoke(name, arguments, actor:, root:, call_id:)
        ChatToolCall.perform(name, arguments, actor: actor, root: root, call_id: call_id)
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

      def self_tool?(name)
        SELF_PREFIXES.any? { |prefix| name.to_s.start_with?(prefix) }
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
        return if self_tool?(name) || !usable_name?(name)
        return if mode == :read && !surface.read_only_tool?(name)

        description = field(definition, :description).to_s.strip
        parameters = json_object(field(definition, :inputSchema))
        return if description.empty? || parameters.nil?

        { type: "function", name: name, description: description, parameters: parameters }
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
