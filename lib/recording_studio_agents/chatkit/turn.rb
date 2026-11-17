# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    class Turn
      def self.open(actor:, root:, text:, **)
        new(actor, root, text, created: true, **)
      end

      def self.follow(actor:, root:, text:, recording:, **)
        new(actor, root, text, created: false, recording: recording, **)
      end

      def initialize(actor, root, text, created:, **options)
        @actor = actor
        @root = root
        @text = text
        @created = created
        assign(options)
      end

      def each(&block)
        return enum_for(:each) unless block

        emit(opening_events, block)
        emit([@terminal], block) if stop?(store)
        return if @terminal

        @model.play { |event| block.call(json(event)) }
      end

      def cancel!
        @model&.cancel!
      end

      private

      def assign(options)
        @recording = options[:recording]
        @page_context = options[:page_context]
        @page_recording = options[:page_recording]
        @request_type = options[:request_type]
        @thread_id = @recording&.id || SecureRandom.uuid
        @item_id = SecureRandom.uuid
        @time = Time.current
      end

      def stop?(recording)
        return true if @terminal

        @model = ModelStream.new(@actor, @root, recording)
        false
      end

      def store
        Timing.measure("page_context") { resolve_context! }
        Timing.measure(store_phase) { save_turn }
      rescue RecordingStudioAI::Errors::UsageDeclined => e
        notice!(e)
      rescue RecordingStudioAI::Errors::ContractValidationError => e
        failed!(e, "chatkit_controller.create")
      rescue Error => e
        failed!(e, "server.call")
      end

      def store_phase
        @created ? "create" : "append"
      end

      def notice!(error)
        ErrorLog.call(error, site: "chatkit_controller.create", type: @request_type)
        @terminal = UsageNotice.event(thread_id: @thread_id)
      rescue Error => e
        failed!(e, "chatkit_controller.create")
      end

      def failed!(error, site)
        ErrorLog.call(error, site: site, type: @request_type)
        @terminal = { type: "error", code: "custom", message: client_message(error), allow_retry: false }
      end

      def client_message(error)
        return "chat was not found" if error.is_a?(IsolationError)

        error.message
      end

      def resolve_context!
        page = @page_recording || @page_context&.page_for(@root, @actor)
        @parent = page || @root
        @preface = @page_context.preface(page) if @page_context
        @model_input = PageContext.model_input(@text, @preface)
      end

      def save_turn
        return create_chat if @created

        append_chat
      end

      def create_chat
        Sessions::Create.call(
          parent_recording: @parent, root_recording: @root, actor: @actor, input: @text,
          provider_input: @model_input, idempotency_key: SecureRandom.uuid, title: @text.truncate(60),
          recording_id: @thread_id, item_id: @item_id, item_created_at: @time
        ).value!
      end

      def append_chat
        Sessions::Append.call(
          root_recording: @root, recording: @recording, actor: @actor, input: @text,
          provider_input: @model_input, idempotency_key: SecureRandom.uuid,
          item_id: @item_id, item_created_at: @time
        ).value!
        @recording
      end

      def opening_events
        Opening.events(created: @created, thread_id: @thread_id, item_id: @item_id, text: @text, time: @time)
      end

      def emit(events, block)
        events.each { |event| block.call(json(event)) }
      end

      def json(payload)
        JSON.generate(payload)
      end
    end

    class Opening
      def self.events(created:, thread_id:, item_id:, text:, time:)
        new(created, thread_id, item_id, text, time).events
      end

      def initialize(created, thread_id, item_id, text, time)
        @created = created
        @thread_id = thread_id
        @item_id = item_id
        @text = text
        @time = time
      end

      def events
        list = []
        list << thread_event if @created
        list << user_event
        list << { type: "stream_options", stream_options: { allow_cancel: true } }
        list
      end

      private

      def thread_event
        recordable = ThreadDraft.new(@text.truncate(60), "active")
        draft = ThreadDraft.recording(@thread_id, recordable, @time)
        { type: "thread.created", thread: Payload.thread(draft, items: { data: [], has_more: false }) }
      end

      def user_event
        item = ThreadDraft.item(@item_id, @text, @time)
        { type: "thread.item.done", item: Payload.user_message(item, @thread_id) }
      end
    end

    # Enough of a recording and an item for the events sent before the rows exist.
    class ThreadDraft
      attr_reader :title, :status

      def self.recording(id, recordable, created_at)
        Struct.new(:id, :recordable, :created_at).new(id, recordable, created_at)
      end

      def self.item(id, text, created_at)
        Struct.new(:id, :text, :created_at).new(id, text, created_at)
      end

      def initialize(title, status)
        @title = title
        @status = status
      end
    end
  end
end
