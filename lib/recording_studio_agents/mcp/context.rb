# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    module Context
      module_function

      def actor(context)
        context.access_grant.actor
      end

      # Permission checks keep using #actor (the access grant's OauthAuthorization).
      # The recorded event uses the OAuth client when this host can stamp authorized_by.
      def event_actor(context)
        grant = context.access_grant
        return grant.actor unless authorized_by_available?(context)

        client = grant.api_client if grant.respond_to?(:api_client)
        client.presence || grant.actor
      end

      def event_metadata(context)
        supplied = supplied_claims(context)
        return context.with_authorized_by(supplied) if context.respond_to?(:with_authorized_by)
        return {} unless context.access_grant.respond_to?(:authorized_by)

        metadata_for(context.access_grant.authorized_by)
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

      def authorized_by_available?(context)
        context.respond_to?(:with_authorized_by) || context.access_grant.respond_to?(:authorized_by)
      end

      def supplied_claims(context)
        claims = {}
        metadata = value(context, :metadata)
        claims.merge!(metadata.to_h.symbolize_keys) if metadata.respond_to?(:to_h) && !metadata.is_a?(String)
        type = value(context, :authorized_by_type)
        id = value(context, :authorized_by_id)
        claims[:authorized_by_type] = type unless type.nil?
        claims[:authorized_by_id] = id unless id.nil?
        claims
      end

      def metadata_for(actor)
        return {} if actor.blank?

        identifier = actor.id if actor.respond_to?(:id)
        return {} if identifier.blank?

        type_name = actor.class.respond_to?(:polymorphic_name) ? actor.class.polymorphic_name : actor.class.name
        return {} if type_name.blank?

        { authorized_by_type: type_name, authorized_by_id: identifier }
      end
    end
  end
end
