# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module GlobalKey
      BINDING_INDEX = "index_rs_agents_bindings_on_create_key"
      ITEM_INDEX = "index_rs_agents_items_on_idempotency_key"

      private

      def reraise_binding_conflict!(error)
        raise_global_binding_conflict!(error) if error.is_a?(ActiveRecord::RecordNotUnique)
        raise error
      end

      def raise_global_binding_conflict!(error)
        return unless error.message.include?(BINDING_INDEX)

        raise IsolationError, "create_idempotency_key is already used in another workspace"
      end

      def reject_global_item_straggler!
        return unless global_item_index?
        return unless foreign_item_key?

        raise IsolationError, "idempotency_key is already used outside this workspace"
      end

      def global_item_index?
        Item.connection.index_exists?(:recording_studio_agents_items, :idempotency_key, name: ITEM_INDEX)
      end

      def foreign_item_key?
        Item.where(idempotency_key: @idempotency_key).where(
          "root_recording_id IS DISTINCT FROM ?", @root_recording.id
        ).exists?
      end

      def raise_global_item_conflict!(error)
        return unless error.message.include?(ITEM_INDEX)

        raise IsolationError, "idempotency_key is already used outside this workspace"
      end
    end
  end
end
