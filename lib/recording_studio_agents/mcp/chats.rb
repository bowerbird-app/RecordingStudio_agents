# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module Chats
      class List
        def self.call(context)
          Context.call do
            root = Context.root(context)
            page = parent_recording(context, root)
            Context.authorize!(context, root, :view) if page.nil?
            listed = Context.catalog(context, page_recording: page).list_threads(
              "limit" => Context.value(context, :limit)
            )
            { chats: listed[:data], has_more: listed[:has_more], after: listed[:after] }
          end
        end

        def self.parent_recording(context, root)
          id = Context.value(context, :parent)
          return if id.blank?

          ScopedParent.resolve!(id, root: root, access_grant: context.access_grant)
        end
        private_class_method :parent_recording
      end

      class Read
        def self.call(context)
          Context.call do
            ChatKit::Payload.thread(viewed(context))
          end
        end

        def self.viewed(context)
          recording = Context.catalog(context).find!(Context.value(context, :id))
          Context.authorize!(context, recording, :view)
          recording
        end
        private_class_method :viewed
      end

      class Create
        def self.call(context)
          Context.call do
            recording = Sessions::Create.call(**create_args(context)).value!
            { id: recording.id, title: recording.recordable.title }
          end
        end

        def self.create_args(context)
          root = Context.root(context)
          parent = parent_recording(context, root) || editable_root(context)
          {
            parent_recording: parent, root_recording: root, actor: Context.actor(context),
            input: Context.value(context, :input), idempotency_key: Context.value(context, :idempotency_key),
            title: Context.value(context, :title), instructions: Context.value(context, :instructions),
            access_grant: context.access_grant
          }
        end
        private_class_method :create_args

        def self.parent_recording(context, root)
          id = Context.value(context, :parent)
          return if id.blank?

          recording = ScopedParent.resolve!(id, root: root, access_grant: context.access_grant)
          Context.authorize!(context, recording, :edit)
          recording
        end
        private_class_method :parent_recording

        def self.editable_root(context)
          root = Context.root(context)
          Context.authorize!(context, root, :edit)
          root
        end
        private_class_method :editable_root
      end

      class Append
        def self.call(context)
          Context.call do
            recording = Sessions::Append.call(**append_args(context)).value!
            { id: recording.id }
          end
        end

        def self.append_args(context)
          root = Context.root(context)
          Context.authorize!(context, root, :edit)
          {
            root_recording: root, actor: Context.actor(context), access_grant: context.access_grant,
            recording_id: Context.value(context, :id), input: Context.value(context, :input),
            idempotency_key: Context.value(context, :idempotency_key)
          }
        end
        private_class_method :append_args
      end
    end
  end
end
