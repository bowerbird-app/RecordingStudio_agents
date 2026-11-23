# frozen_string_literal: true

require "recording_studio_agents/api/tool_copy"

module RecordingStudioAgents
  module Mcp
    module Contracts
      module_function

      def list
        {
          fields: {
            limit: { type: :integer, required: false, description: Api::ToolCopy::LIST_LIMIT },
            parent: parent_field(Api::ToolCopy::LIST_PARENT)
          }
        }
      end

      def create
        return { fields: create_fields } unless defined?(RecordingStudioApi::ActionInputContract)

        require "recording_studio_agents/mcp/client_claims"
        require "recording_studio_agents/mcp/instructions_contract"
        InstructionsContract.new(fields: create_fields)
      end

      def create_fields
        {
          input: input_field,
          idempotency_key: create_key_field,
          title: title_field,
          instructions: instructions_field,
          parent: parent_field
        }
      end

      def parent_field(description = Api::ToolCopy::PARENT)
        {
          type: :string, required: false,
          description: description
        }
      end

      def input_field
        { type: :string, required: true, allow_blank: false, description: Api::ToolCopy::CREATE_INPUT }
      end

      def create_key_field
        {
          type: :string, required: true, allow_blank: false,
          description: Api::ToolCopy::CREATE_KEY
        }
      end

      def title_field
        { type: :string, required: false, description: Api::ToolCopy::TITLE }
      end

      def instructions_field
        limit = RecordingStudioAgents.configuration.max_instructions_length
        {
          type: :string, required: false, maxLength: limit,
          description: Api::ToolCopy.instructions(limit)
        }
      end

      def id
        { fields: { id: { type: :string, required: true, allow_blank: false, description: Api::ToolCopy::CHAT_ID } } }
      end

      def append
        {
          fields: {
            id: { type: :string, required: true, allow_blank: false, description: Api::ToolCopy::CHAT_ID },
            input: { type: :string, required: true, allow_blank: false, description: Api::ToolCopy::APPEND_INPUT },
            idempotency_key: {
              type: :string, required: true, allow_blank: false,
              description: Api::ToolCopy::APPEND_KEY
            }
          }
        }
      end

      def items
        {
          fields: {
            id: { type: :string, required: true, allow_blank: false, description: Api::ToolCopy::CHAT_ID },
            limit: { type: :integer, required: false, description: Api::ToolCopy::ITEM_LIMIT },
            order: { type: :string, required: false, description: Api::ToolCopy::ORDER }
          }
        }
      end

      def item
        {
          fields: {
            id: { type: :string, required: true, allow_blank: false, description: Api::ToolCopy::CHAT_ID },
            item_id: { type: :string, required: true, allow_blank: false, description: Api::ToolCopy::ITEM_ID }
          }
        }
      end
    end
  end
end
