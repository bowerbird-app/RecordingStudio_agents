# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module Contracts
      module_function

      def list
        { fields: { limit: { type: :integer, required: false, description: "Page size." }, parent: parent_field } }
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

      def parent_field
        {
          type: :string, required: false,
          description: "Optional parent id. Chats are created under it and listed only there. " \
                       "Omit it for the whole workspace. The parent must be inside this workspace and viewable."
        }
      end

      def input_field
        { type: :string, required: true, allow_blank: false, description: "First user message." }
      end

      def create_key_field
        {
          type: :string, required: true, allow_blank: false,
          description: "Create key. Unique inside this workspace."
        }
      end

      def title_field
        { type: :string, required: false, description: "Optional chat title." }
      end

      def instructions_field
        limit = RecordingStudioAgents.configuration.max_instructions_length
        {
          type: :string, required: false, maxLength: limit,
          description: "Optional extra instructions, at most #{limit} characters. " \
                       "Blank uses the host default. A real override is appended after that default " \
                       "when config.instructions_override allows it."
        }
      end

      def id
        { fields: { id: { type: :string, required: true, allow_blank: false, description: "Chat id." } } }
      end

      def append
        {
          fields: {
            id: { type: :string, required: true, allow_blank: false, description: "Chat id." },
            input: { type: :string, required: true, allow_blank: false, description: "User message." },
            idempotency_key: {
              type: :string, required: true, allow_blank: false,
              description: "Message key. Unique inside this workspace."
            }
          }
        }
      end

      def items
        {
          fields: {
            id: { type: :string, required: true, allow_blank: false, description: "Chat id." },
            limit: { type: :integer, required: false },
            order: { type: :string, required: false, description: "asc or desc." }
          }
        }
      end

      def item
        {
          fields: {
            id: { type: :string, required: true, allow_blank: false, description: "Chat id." },
            item_id: { type: :string, required: true, allow_blank: false, description: "Item id." }
          }
        }
      end
    end
  end
end
