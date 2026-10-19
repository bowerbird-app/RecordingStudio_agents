# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module Contracts
      module_function

      def list
        { fields: { limit: { type: :integer, required: false, description: "Page size." } } }
      end

      def create
        {
          fields: {
            input: { type: :string, required: true, allow_blank: false, description: "First user message." },
            idempotency_key: {
              type: :string, required: true, allow_blank: false,
              description: "Create key. Unique inside this workspace."
            },
            title: { type: :string, required: false, description: "Optional chat title." }
          }
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
