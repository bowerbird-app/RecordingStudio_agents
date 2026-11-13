# frozen_string_literal: true

module RecordingStudioAgents
  module ChatKit
    # Host page facts sent with a chat request. The client sends data.
    # This builds the model preface. It never accepts an instructions field.
    class PageContext
      HEADER = "X-Recording-Studio-Agents-Page"
      URL_LIMIT = 2048
      TITLE_LIMIT = 300
      SELECTION_LIMIT = 2000
      METADATA_LIMIT = 2048
      METADATA_KEYS = 20
      METADATA_KEY_LIMIT = 40
      METADATA_VALUE_LIMIT = 200
      HEADER_LIMIT = 8192

      def self.parse(raw)
        return new({}) if raw.blank?
        raise ProtocolError, "page context is too large" if raw.bytesize > HEADER_LIMIT

        data = JSON.parse(raw)
        raise ProtocolError, "page context must be an object" unless data.is_a?(Hash)
        raise ProtocolError, "ChatKit does not accept instructions" if instructions?(data)

        new(data)
      rescue JSON::ParserError
        raise ProtocolError, "page context must be an object"
      end

      def self.model_input(text, preface)
        return text if preface.blank?

        "#{preface}\n\n#{text}"
      end

      def self.instructions?(data)
        return true if data.key?("instructions") || data.key?(:instructions)

        bag = data["metadata"] || data[:metadata]
        bag.is_a?(Hash) && (bag.key?("instructions") || bag.key?(:instructions))
      end

      def initialize(data)
        @url = clip(data["url"], URL_LIMIT)
        @title = clip(data["title"], TITLE_LIMIT)
        @selection = clip(data["selection"], SELECTION_LIMIT)
        @page_recording_id = uuid(data["page_recording_id"])
        @metadata = metadata(data["metadata"])
      end

      def page_for(root, actor)
        return if @page_recording_id.nil?

        ScopedParent.resolve!(@page_recording_id, root: root, actor: actor)
      rescue ProtocolError
        nil
      end

      def preface(page_recording = nil)
        lines = []
        lines << "URL: #{@url}" if @url
        lines << "Title: #{@title}" if @title
        page = page_line(page_recording)
        lines << page if page
        lines << "Selection: #{@selection}" if @selection
        lines << "Metadata: #{JSON.generate(@metadata)}" if @metadata.any?
        return if lines.empty?

        "Page context:\n#{lines.join("\n")}"
      end

      private

      def page_line(page_recording)
        return if page_recording.nil? || @page_recording_id.nil?
        return unless page_recording.id.to_s == @page_recording_id

        "Page: #{page_recording.id}"
      end

      def clip(value, limit)
        return unless value.is_a?(String)

        text = value.strip
        return if text.empty?

        text[0, limit]
      end

      def uuid(value)
        return unless value.is_a?(String)

        text = value.strip
        text if text.match?(ScopedParent::UUID)
      end

      def metadata(value)
        return {} unless value.is_a?(Hash)

        kept = {}
        value.each do |key, entry|
          break if kept.size >= METADATA_KEYS

          name = metadata_key(key)
          stored = metadata_value(entry)
          next if name.nil? || stored.nil?

          kept[name] = stored
        end
        trim_metadata(kept)
      end

      def trim_metadata(kept)
        kept.delete(kept.keys.last) while kept.any? && JSON.generate(kept).bytesize > METADATA_LIMIT
        kept
      end

      def metadata_key(key)
        return unless key.is_a?(String)

        name = key.strip
        return if name.empty? || name == "instructions" || name.length > METADATA_KEY_LIMIT
        return unless name.match?(/\A[A-Za-z0-9_]+\z/)

        name
      end

      def metadata_value(entry)
        case entry
        when TrueClass, FalseClass, Integer then entry
        when Float then entry if entry.finite?
        when String then clip(entry, METADATA_VALUE_LIMIT)
        end
      end
    end
  end
end
