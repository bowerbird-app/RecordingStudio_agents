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

      def catalog(context, page_recording: nil)
        ChatKit::Catalog.new(actor(context), root(context), page_recording: page_recording)
      end

      def call
        yield
      rescue ChatKit::ProtocolError => e then raise_protocol!(e)
      # During the A to B window this says only that the key string exists in another workspace.
      rescue KeyConflictError => e then raise_conflict!(e)
      rescue IsolationError then raise RecordingStudioApi::NotFoundError, "chat was not found"
      rescue Sessions::AccessDeniedError => e then raise RecordingStudioApi::AuthorizationError, e.message
      rescue Error => e then raise RecordingStudioApi::InvalidActionInputError, e.message
      end

      def raise_conflict!(error)
        message = "conflict: #{error.message}"
        raise RecordingStudioApi::InvalidActionInputError.new(message, details: ["conflict"])
      end

      def raise_protocol!(error)
        raise RecordingStudioApi::AuthorizationError, error.message if error.status == 403
        raise RecordingStudioApi::InvalidActionInputError, error.message if error.status == 422

        raise RecordingStudioApi::NotFoundError, error.message
      end
    end
  end
end
