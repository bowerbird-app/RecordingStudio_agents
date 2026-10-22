# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    class Turn
      def self.open(actor:, root:, text:, recording: nil, parent: nil)
        created = recording.nil?
        recording = created ? create(actor, root, text, parent || root) : append(actor, root, recording, text)
        new(actor, root, recording, created: created)
      end

      def self.create(actor, root, text, parent)
        Sessions::Create.call(
          parent_recording: parent, root_recording: root, actor: actor, input: text,
          idempotency_key: SecureRandom.uuid, title: text.truncate(60)
        ).value!
      end

      def self.append(actor, root, recording, text)
        Sessions::Append.call(
          root_recording: root, recording: recording, actor: actor, input: text, idempotency_key: SecureRandom.uuid
        ).value!
        recording
      end

      def initialize(actor, root, recording, created:)
        @actor = actor
        @recording = recording
        @created = created
        @model = ModelStream.new(actor, root, recording)
      end

      def each(&block)
        return enum_for(:each) unless block

        emit(opening, block)
        @model.play { |event| block.call(json(event)) }
      end

      def cancel!
        @model.cancel!
      end

      private

      def emit(events, block)
        events.each { |event| block.call(json(event)) }
      end

      def opening
        events = []
        events << thread_event if @created
        events << user_event
        events << stream_options
        events
      end

      def thread_event
        { type: "thread.created", thread: Payload.thread(@recording, items: { data: [], has_more: false }) }
      end

      def user_event
        { type: "thread.item.done", item: Payload.user_message(latest_user_item, @recording.id) }
      end

      def stream_options
        { type: "stream_options", stream_options: { allow_cancel: true } }
      end

      def latest_user_item
        Item.where(recording_id: @recording.id, role: "user").order(created_at: :desc).first
      end

      def json(payload)
        JSON.generate(payload)
      end
    end
  end
end
