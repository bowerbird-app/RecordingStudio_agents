# frozen_string_literal: true

require "digest"
require "json"

module RecordingStudioAgents
  class ActionMenu
    class Candidate
      attr_reader :id, :type, :tool_key, :tool_version, :arguments, :purpose,
                  :handoff_key, :handoff_version, :argument_digest

      def initialize(id:, type:, purpose:, tool_key: nil, tool_version: nil, arguments: nil,
                     handoff_key: nil, handoff_version: nil, argument_digest: nil)
        @id = id.to_s
        @type = type.to_s
        @purpose = purpose.to_s
        @tool_key = tool_key&.to_s
        @tool_version = tool_version&.to_i
        @arguments = arguments
        @handoff_key = handoff_key&.to_s
        @handoff_version = handoff_version&.to_i
        @argument_digest = argument_digest.presence || digest_of(arguments)
        freeze
      end

      def tool?
        type == "tool"
      end

      def deliver?
        type == "deliver"
      end

      def handoff?
        type == "handoff"
      end

      def usable?
        return true if deliver? || handoff?
        return false unless tool?

        arguments.is_a?(Hash)
      end

      def index_entry
        {
          "id" => id,
          "type" => type,
          "tool_key" => tool_key,
          "tool_version" => tool_version,
          "argument_digest" => argument_digest,
          "purpose" => purpose,
          "handoff_key" => handoff_key,
          "handoff_version" => handoff_version
        }
      end

      def self.digest_of(arguments)
        return if arguments.nil?

        Digest::SHA256.hexdigest(JSON.generate(arguments))
      end

      private

      def digest_of(arguments)
        self.class.digest_of(arguments)
      end
    end

    def self.admit(raw_candidates, program:, refused_digests:)
      menu = new
      Array(raw_candidates).each do |raw|
        candidate = build(raw, program)
        next if candidate.nil?
        next if candidate.tool? && refused_digests.include?(candidate.argument_digest)

        menu.add(candidate)
      end
      menu
    end

    def self.build(raw, program)
      item = raw.is_a?(Hash) ? raw.stringify_keys : nil
      return unless item

      id = item["id"].to_s.strip
      type = item["type"].to_s
      purpose = item["purpose"].to_s.strip
      return if id.empty? || purpose.empty?
      return unless %w[tool deliver handoff].include?(type)

      case type
      when "tool"
        key = item["tool_key"].to_s
        version = item["tool_version"].to_i
        return unless program_allows_tool?(program, key, version)
        return unless item["arguments"].is_a?(Hash)

        Candidate.new(
          id: id, type: type, purpose: purpose, tool_key: key, tool_version: version,
          arguments: item["arguments"]
        )
      when "handoff"
        key = item["handoff_key"].to_s
        version = item["handoff_version"].to_i
        return unless program.allows_handoff?(key, version)

        Candidate.new(id: id, type: type, purpose: purpose, handoff_key: key, handoff_version: version)
      else
        Candidate.new(id: id, type: type, purpose: purpose)
      end
    end

    def self.program_allows_tool?(program, key, version)
      program.tool_references.any? { |reference| reference.key == key && reference.version == version }
    end

    def initialize(candidates = [])
      @candidates = {}
      candidates.each { |candidate| add(candidate) }
    end

    def add(candidate)
      @candidates[candidate.id] = candidate
      self
    end

    def fetch(id)
      @candidates[id.to_s]
    end

    def include?(id)
      @candidates.key?(id.to_s)
    end

    def actionable
      @candidates.values.select(&:usable?)
    end

    def tools
      actionable.select(&:tool?)
    end

    def deliver?(id)
      fetch(id)&.deliver?
    end

    def consume(id)
      @candidates.delete(id.to_s)
    end

    def index
      @candidates.values.map(&:index_entry)
    end

    def restore_terminal(index_entries)
      Array(index_entries).each do |entry|
        item = entry.stringify_keys
        next unless %w[deliver handoff].include?(item["type"])

        add(Candidate.new(
              id: item["id"], type: item["type"], purpose: item["purpose"].to_s,
              handoff_key: item["handoff_key"], handoff_version: item["handoff_version"],
              argument_digest: item["argument_digest"]
            ))
      end
      self
    end
  end
end
