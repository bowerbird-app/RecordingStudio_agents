# frozen_string_literal: true

module RecordingStudioAgents
  module Sessions
    # ChatKit chooses the thread id before the row exists, then the insert
    # uses that id. A refresh loads the same thread instead of a second one.
    module AssignedChatId
      KEY = :recording_studio_agents_assigned_chat_id

      module_function

      def with(id)
        install!
        return yield if id.blank?

        previous = Thread.current[KEY]
        Thread.current[KEY] = id
        yield
      ensure
        Thread.current[KEY] = previous if id.present?
      end

      def apply(attributes)
        id = Thread.current[KEY]
        return attributes unless id && attributes.is_a?(Hash)
        return attributes unless chat?(attributes[:recordable] || attributes["recordable"])
        return attributes if attributes.key?(:id) || attributes.key?("id")

        attributes.merge(id: id)
      end

      def chat?(recordable)
        recordable.is_a?(RecordingStudioAgents::Session)
      end

      def install!
        return unless defined?(RecordingStudio::Recording)

        owner = RecordingStudio::Recording.singleton_class
        return if owner.ancestors.include?(Create)

        owner.prepend(Create)
      end

      module Create
        def create!(attributes = nil, &)
          super(AssignedChatId.apply(attributes), &)
        end
      end

      install!
    end
  end
end
