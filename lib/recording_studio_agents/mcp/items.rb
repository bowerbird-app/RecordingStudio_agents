# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module Items
      class List
        def self.call(context)
          Context.call do
            recording = Context.catalog(context).find!(Context.value(context, :id))
            page = ChatKit::Payload.item_page(recording, item_params(context))
            { items: page[:data], has_more: page[:has_more], after: page[:after] }
          end
        end

        def self.item_params(context)
          { "limit" => Context.value(context, :limit), "order" => Context.value(context, :order) }
        end
        private_class_method :item_params
      end

      class Read
        def self.call(context)
          Context.call do
            recording = Context.catalog(context).find!(Context.value(context, :id))
            item = Item.find_by(id: Context.value(context, :item_id), recording_id: recording.id)
            raise ChatKit::ProtocolError.new("item was not found", status: 404) if item.nil?

            ChatKit::Payload.item(item, recording.id)
          end
        end
      end
    end
  end
end
