# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    module GlobalKey
      BINDING_INDEX = "index_rs_agents_bindings_on_create_key"
      ITEM_INDEX = "index_rs_agents_items_on_idempotency_key"

      class << self
        attr_accessor :item_index_present, :binding_index_present

        def reset_index_cache!
          self.item_index_present = nil
          self.binding_index_present = nil
        end
      end

      private

      def resume_after_binding_insert(hosted, error)
        abandon(hosted)
        found = existing_recording if error.is_a?(ActiveRecord::RecordNotUnique)
        return found if found

        reraise_binding_conflict!(error)
      end

      def reraise_binding_conflict!(error)
        raise_global_binding_conflict!(error) if error.is_a?(ActiveRecord::RecordNotUnique)
        raise error
      end

      def raise_global_binding_conflict!(error)
        return unless error.message.include?(BINDING_INDEX)

        raise KeyConflictError, "create_idempotency_key is already used in another workspace"
      end

      def reject_global_binding_straggler!
        return unless global_binding_index?
        return unless foreign_binding_key?

        raise KeyConflictError, "create_idempotency_key is already used in another workspace"
      end

      def reject_global_item_straggler!
        return unless global_item_index?
        return unless foreign_item_key?

        raise KeyConflictError, "idempotency_key is already used outside this workspace"
      end

      def global_binding_index?
        cached_index(:binding_index_present) do
          Binding.connection.index_exists?(
            :recording_studio_agents_bindings, :create_idempotency_key, name: BINDING_INDEX
          )
        end
      end

      def global_item_index?
        cached_index(:item_index_present) do
          Item.connection.index_exists?(:recording_studio_agents_items, :idempotency_key, name: ITEM_INDEX)
        end
      end

      def cached_index(name)
        return false if GlobalKey.public_send(name) == false

        present = yield
        GlobalKey.public_send("#{name}=", false) unless present
        present
      end

      def foreign_binding_key?
        Binding.where(create_idempotency_key: @idempotency_key).where(
          "root_recording_id IS DISTINCT FROM ?", @root_recording.id
        ).exists?
      end

      def foreign_item_key?
        Item.where(idempotency_key: @idempotency_key).where(
          "root_recording_id IS DISTINCT FROM ?", @root_recording.id
        ).exists?
      end

      def raise_global_item_conflict!(error)
        return unless error.message.include?(ITEM_INDEX)

        raise KeyConflictError, "idempotency_key is already used outside this workspace"
      end
    end
  end
end
