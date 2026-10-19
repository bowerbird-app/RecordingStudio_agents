# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module Context
      module_function

      def actor(context)
        context.access_grant.actor
      end

      def authorize!(context, recording, role)
        context.access_grant.authorize!(recording: recording, role: role)
      end

      def root(context)
        recording = context.root_recording
        raise Error, "root is required" if recording.nil?

        recording
      end

      def value(context, key)
        params = context.params || {}
        params[key] || params[key.to_s] || params[key.to_sym]
      end

      def catalog(context)
        ChatKit::Catalog.new(actor(context), root(context))
      end

      def call
        yield
      rescue ChatKit::ProtocolError => e
        raise_protocol!(e)
      rescue IsolationError => e
        raise RecordingStudioApi::NotFoundError, isolation_message(e)
      rescue Sessions::AccessDeniedError => e
        raise RecordingStudioApi::AuthorizationError, e.message
      rescue Error => e
        raise RecordingStudioApi::InvalidActionInputError, e.message
      end

      # A missing chat stays a generic 404 so a refused workspace does not reveal that it exists.
      # A key already used in another workspace is the caller's own key, so the message can say that.
      def isolation_message(error)
        text = error.message.to_s
        return text if text.include?("already used")

        "chat was not found"
      end

      def raise_protocol!(error)
        raise RecordingStudioApi::AuthorizationError, error.message if error.status == 403

        raise RecordingStudioApi::NotFoundError, error.message
      end
    end
  end
end
