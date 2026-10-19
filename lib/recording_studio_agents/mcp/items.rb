# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module Items
      class List
        def self.call(context)
          Context.call do
            page = ChatKit::Payload.item_page(viewed_chat(context), item_params(context))
            { items: page[:data], has_more: page[:has_more], after: page[:after] }
          end
        end

        def self.item_params(context)
          { "limit" => Context.value(context, :limit), "order" => Context.value(context, :order) }
        end
        private_class_method :item_params

        def self.viewed_chat(context)
          recording = Context.catalog(context).find!(Context.value(context, :id))
          Context.authorize!(context, recording, :view)
          recording
        end
        private_class_method :viewed_chat
      end

      class Read
        def self.call(context)
          Context.call do
            recording = viewed_chat(context)
            item = Item.find_by(id: Context.value(context, :item_id), recording_id: recording.id)
            raise ChatKit::ProtocolError.new("item was not found", status: 404) if item.nil?

            ChatKit::Payload.item(item, recording.id)
          end
        end

        def self.viewed_chat(context)
          recording = Context.catalog(context).find!(Context.value(context, :id))
          Context.authorize!(context, recording, :view)
          recording
        end
        private_class_method :viewed_chat
      end
    end
  end
end
