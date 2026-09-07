# frozen_string_literal: true

module RecordingStudioAgents
  class Progress
    Step = Data.define(:kind, :label, :status, :badge, :badge_style)

    BADGES = {
      done: { badge: "Done", badge_style: :success },
      running: { badge: "Working", badge_style: :info },
      waiting: { badge: "Waiting", badge_style: :warning },
      failed: { badge: "Failed", badge_style: :danger }
    }.freeze

    TOOL_STATUSES = {
      "requested" => :running,
      "authorized" => :running,
      "running" => :running,
      "awaiting_confirmation" => :waiting,
      "completed" => :done,
      "denied" => :failed,
      "rejected" => :failed,
      "failed" => :failed,
      "cancelled" => :failed
    }.freeze

    KNOWLEDGE_LABEL = "Checked this workspace"
    WAITING_LABEL = "Waiting on a yes"
    HANDOFF_LABEL = "Asked for a reviewer"
    FINISHED_LABEL = "Done"
    FAILED_LABEL = "Did not finish"
    RUNNING_LABEL = "On it"

    def self.for(run)
      new(run).steps
    end

    def initialize(run)
      @run = run
    end

    def steps
      collected = []
      collected << knowledge_step if knowledge_loaded?
      collected.concat(tool_steps)
      closing = status_step_for(collected)
      collected << closing if closing
      collected
    end

    private

    def knowledge_loaded?
      activities.any? { |activity| activity.kind.to_s == "knowledge_loaded" }
    end

    def knowledge_step
      step(:knowledge, KNOWLEDGE_LABEL, :done)
    end

    def tool_steps
      invocations.filter_map do |invocation|
        key = read(invocation, :tool_key).to_s
        next if key == Handoffs::INTERNAL_TOOL_KEY.to_s

        step(:tool, tool_label(invocation), tool_status(invocation))
      end
    end

    def status_step_for(collected)
      case @run.status.to_s
      when "awaiting_confirmation"
        return if collected.any? { |item| item.status == :waiting }

        step(:confirmation, WAITING_LABEL, :waiting)
      when "handoff_requested"
        step(:handoff, HANDOFF_LABEL, :done)
      when "failed", "cancelled"
        step(:failed, FAILED_LABEL, :failed)
      when "succeeded"
        step(:finished, FINISHED_LABEL, :done)
      when "running", "pending"
        return if collected.any? { |item| item.kind == :tool }

        step(:running, RUNNING_LABEL, :running)
      end
    end

    def tool_label(invocation)
      snapshot = read(invocation, :tool_name_snapshot)
      return snapshot.to_s if snapshot.present?

      read(invocation, :tool_key).to_s.tr("_", " ").sub(/\A./, &:upcase)
    end

    def tool_status(invocation)
      TOOL_STATUSES.fetch(read(invocation, :status).to_s, :running)
    end

    def activities
      return [] unless @run.respond_to?(:run_activities)

      records = @run.run_activities
      records = records.order(:sequence) if records.respond_to?(:order)
      Array(records)
    rescue StandardError
      []
    end

    def invocations
      run = ai_run
      return [] unless run&.respond_to?(:custom_tool_invocations)

      records = run.custom_tool_invocations
      if records.respond_to?(:order)
        records = records.order(:created_at, :id)
      else
        records = Array(records).sort_by do |item|
          [read(item, :created_at) || Time.at(0), read(item, :id).to_i]
        end
      end
      Array(records)
    rescue StandardError
      []
    end

    def ai_run
      return @ai_run if defined?(@ai_run)

      @ai_run = lookup_ai_run
    end

    def lookup_ai_run
      found = lookup_ai_run_by_id
      return found if found

      Ai.find_run(request_id: Ai.request_id_for(@run))
    rescue StandardError
      nil
    end

    def lookup_ai_run_by_id
      id = @run.recording_studio_ai_run_id
      return if id.blank?

      klass = ai_run_class
      return unless klass

      klass.find_by(id: id)
    rescue StandardError
      nil
    end

    def ai_run_class
      return unless defined?(RecordingStudioAI::Run)

      RecordingStudioAI::Run
    rescue StandardError
      nil
    end

    def read(record, key)
      if record.respond_to?(key)
        record.public_send(key)
      elsif record.respond_to?(:[])
        record[key] || record[key.to_s]
      end
    end

    def step(kind, label, status)
      badge = BADGES.fetch(status)
      Step.new(kind: kind, label: label, status: status, badge: badge[:badge], badge_style: badge[:badge_style])
    end
  end
end
