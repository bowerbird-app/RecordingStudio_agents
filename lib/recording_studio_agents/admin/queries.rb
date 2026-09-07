# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    module Queries
      PERIOD = 30.days
      HUNGRY_LIMIT = 5
      BLANK = "-"
      WAITING_STATUSES = %w[pending running awaiting_confirmation].freeze
      AI_JOIN = <<~SQL.squish
        INNER JOIN recording_studio_ai_runs
          ON recording_studio_ai_runs.id = recording_studio_agents_agent_runs.recording_studio_ai_run_id
      SQL

      ByAgentRow = Data.define(
        :agent_key,
        :agent_version,
        :attempts,
        :succeeded,
        :failed,
        :waiting,
        :avg_tokens,
        :avg_latency_ms,
        :avg_tools,
        :ai_sample_count
      )

      module_function

      def agents
        RecordingStudioAgents.agents.all
      end

      def skills
        RecordingStudioAgents.skills.all
      end

      def skill_packs
        RecordingStudioAgents.skill_packs.all
      end

      def tasks(context:)
        Task.where(root_recording_id: visible_root_ids(context)).order(created_at: :desc)
      end

      def runs(context:)
        AgentRun.where(root_recording_id: visible_root_ids(context)).order(created_at: :desc)
      end

      def evaluations(context:)
        Evaluation.joins(:agent_run).where(
          recording_studio_agents_agent_runs: { root_recording_id: visible_root_ids(context) }
        ).order(created_at: :desc)
      end

      def recent_failed_runs(context:)
        runs(context: context).where(status: "failed").limit(5)
      end

      def visible_root_ids(context)
        actor = context.current_actor
        return [] if actor.blank? || !defined?(::RecordingStudioAccessible)

        ::RecordingStudioAccessible.root_recording_ids_for(actor: actor, minimum_role: :view)
      end

      def current_period(now: Time.current)
        (now - PERIOD)..now
      end

      def previous_period(now: Time.current)
        (now - (PERIOD * 2))...(now - PERIOD)
      end

      def attempts_in_period(root_ids:, range:)
        AgentRun.where(root_recording_id: root_ids, created_at: range).count
      end

      def tokens_in_period(root_ids:, range:)
        return 0 unless ai_runs_available?

        AgentRun.where(root_recording_id: root_ids, created_at: range)
                .joins(AI_JOIN)
                .where("recording_studio_ai_runs.total_tokens IS NOT NULL")
                .sum("recording_studio_ai_runs.total_tokens")
                .to_i
      end

      def hungry_agents(root_ids:, range:, limit: HUNGRY_LIMIT)
        return [] unless ai_runs_available?

        totals = AgentRun.where(root_recording_id: root_ids, created_at: range)
                         .joins(AI_JOIN)
                         .where("recording_studio_ai_runs.total_tokens IS NOT NULL")
                         .group(:agent_key)
                         .sum("recording_studio_ai_runs.total_tokens")

        totals.sort_by { |key, tokens| [-tokens.to_i, key.to_s] }
              .first(limit)
              .filter_map do |key, tokens|
                next unless tokens.to_i.positive?

                { agent_key: key, tokens: tokens.to_i }
              end
      end

      def by_agent_rows(root_ids:, range:)
        runs = AgentRun.where(root_recording_id: root_ids, created_at: range).to_a
        ai_by_id = ai_runs_by_id(runs.map(&:recording_studio_ai_run_id))

        runs.group_by { |run| [run.agent_key, run.agent_version] }
            .map { |(key, version), group| build_by_agent_row(key, version, group, ai_by_id) }
            .sort_by { |row| [-row.attempts, row.agent_key.to_s, row.agent_version.to_i] }
      end

      def selected_time_range(context, screen:)
        value = context.filter_value(:date_range) if context.respond_to?(:filter_value)
        value ||= date_range_from_params(context, screen: screen)
        time_range_for(value) || current_period
      end

      def time_range_for(value)
        return unless value.respond_to?(:start_date) && value.respond_to?(:end_date)
        return unless value.start_date && value.end_date

        value.start_date.beginning_of_day..value.end_date.end_of_day
      end

      def distinct_agent_keys
        return [] unless AgentRun.table_exists?

        AgentRun.distinct.order(:agent_key).pluck(:agent_key)
      rescue StandardError
        []
      end

      def ai_runs_available?
        klass = ai_run_class
        return false unless klass
        return false unless klass.respond_to?(:table_exists?)

        klass.table_exists?
      rescue StandardError
        false
      end

      def ai_run_class
        return @ai_run_class if instance_variable_defined?(:@ai_run_class) && !@ai_run_class.nil?
        return RecordingStudioAI::Run if defined?(RecordingStudioAI::Run)

        nil
      end

      def use_ai_run_class!(klass)
        @ai_run_class = klass
      end

      def reset_ai_run_class!
        remove_instance_variable(:@ai_run_class) if instance_variable_defined?(:@ai_run_class)
      end

      def ai_run_for(id)
        return if id.blank? || !ai_runs_available?

        cache = Thread.current[:recording_studio_agents_ai_runs] ||= {}
        return cache[id] if cache.key?(id)

        cache[id] = ai_run_class.find_by(id: id)
      end

      def ai_runs_by_id(ids)
        clean_ids = ids.compact.uniq
        return {} if clean_ids.empty? || !ai_runs_available?

        ai_run_class.where(id: clean_ids).index_by(&:id).tap do |found|
          cache = Thread.current[:recording_studio_agents_ai_runs] ||= {}
          found.each { |id, run| cache[id] = run }
        end
      end

      def clear_ai_run_cache!
        Thread.current[:recording_studio_agents_ai_runs] = nil
      end

      def format_tokens(value)
        return BLANK if value.nil?

        delimited_number(value)
      end

      def format_tools(value)
        return BLANK if value.nil?

        delimited_number(value)
      end

      def compact_tokens(value)
        count = value.to_i
        return "0" if count.zero?
        return compact_millions(count) if count >= 1_000_000
        return compact_thousands(count) if count >= 1_000

        count.to_s
      end

      def delimited_number(value)
        ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
      end

      def percentage_change_label(current:, previous:)
        return "0%" if current.to_i.zero? && previous.to_i.zero?
        return "+100%" if previous.to_i.zero? && current.to_i.positive?

        format("%+.0f%%", ((current - previous) / previous.to_f) * 100)
      end

      def screen_href(context, key, **params)
        return unless context.respond_to?(:admin_screen_path)

        path = context.admin_screen_path(key)
        query = params.compact
        return path if query.empty?

        "#{path}?#{query.to_query}"
      end

      def hungry_label(agent_key:, tokens:)
        "#{agent_key} · #{compact_tokens(tokens)} tokens"
      end

      def tools_cell(row, context)
        ai_run = ai_run_for(row.recording_studio_ai_run_id)
        return BLANK if ai_run.nil?

        count = ai_run.custom_tool_invocation_count.to_i
        return count.to_s if count.zero?

        href = screen_href(context, "tool_calls", run_id: ai_run.id)
        return delimited_number(count) if href.blank?

        ActionController::Base.helpers.link_to(
          delimited_number(count),
          href,
          class: "text-(--color-primary-background-color)",
          data: { turbo_frame: "_top" }
        )
      end

      def ai_run_cell(row, context)
        id = row.recording_studio_ai_run_id
        return BLANK if id.blank?

        href = screen_href(context, "ai_calls", search: id)
        return id.to_s if href.blank?

        ActionController::Base.helpers.link_to(
          id.to_s,
          href,
          class: "text-(--color-primary-background-color)",
          data: { turbo_frame: "_top" }
        )
      end

      def build_by_agent_row(key, version, group, ai_by_id)
        ai_rows = group.filter_map { |run| ai_by_id[run.recording_studio_ai_run_id] }

        ByAgentRow.new(
          agent_key: key,
          agent_version: version,
          attempts: group.size,
          succeeded: count_status(group, "succeeded"),
          failed: count_status(group, "failed"),
          waiting: group.count { |run| WAITING_STATUSES.include?(run.status) },
          avg_tokens: average(ai_rows.filter_map(&:total_tokens)),
          avg_latency_ms: average(ai_rows.filter_map(&:latency_ms)),
          avg_tools: average(ai_rows.filter_map(&:custom_tool_invocation_count)),
          ai_sample_count: ai_rows.size
        )
      end
      private_class_method :build_by_agent_row

      def count_status(group, status)
        group.count { |run| run.status == status }
      end
      private_class_method :count_status

      def average(values)
        numbers = values.compact
        return if numbers.empty?

        (numbers.sum.to_f / numbers.size).round
      end
      private_class_method :average

      def date_range_from_params(context, screen:)
        filter = Array(screen.filters).find { |item| item.key == :date_range }
        return unless filter

        params = context.respond_to?(:params) ? context.params : {}
        filter.normalize(params || {})
      end
      private_class_method :date_range_from_params

      def compact_thousands(count)
        "#{trimmed_units(count / 1000.0)}k"
      end
      private_class_method :compact_thousands

      def compact_millions(count)
        "#{trimmed_units(count / 1_000_000.0)}M"
      end
      private_class_method :compact_millions

      def trimmed_units(value)
        rounded = value.round(1)
        (rounded % 1).zero? ? rounded.to_i : rounded
      end
      private_class_method :trimmed_units
    end
  end
end
