# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # The actor's tool grant and tool surface for one chat turn.
    # Built once and passed into the write check, the audit kind, and the call.
    # It decides which tools exist and whether each name is a read or a write.
    # A write still goes through Recording Studio and Accessible when it runs.
    class TurnTools
      def self.build(actor:, root:)
        new(actor, root).load
      end

      def initialize(actor, root)
        @actor = actor
        @root = root
        @loaded = false
      end

      attr_reader :grant, :surface

      def load
        return self if @loaded

        @loaded = true
        load_surface
        self
      end

      def definitions
        Array(@definitions).presence
      end

      def kind_for(name)
        ChatTools.kind_for(name, self)
      end

      def read_only?(name)
        return false if @surface.nil?

        @surface.read_only_tool?(name)
      end

      private

      def load_surface
        return unless ChatTools.installed?

        @grant = ChatTools.grant_for(@actor, @root)
        return if @grant.nil?

        @surface = RecordingStudioMcp::ToolSurface.for(access_grant: @grant)
        @definitions = listed_definitions unless ChatTools.off?
      end

      def listed_definitions
        @surface.tool_definitions.filter_map { |definition| ChatTools.function_tool(@surface, definition) }
      end
    end
  end
end
