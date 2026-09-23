# frozen_string_literal: true

class PlaygroundController < ApplicationController
  Form = Data.define(:agent, :goal, :context, :extra_skills, :pack)
  StepLine = Data.define(:label, :badge, :badge_style)
  WORKING = StepLine.new(label: "On it", badge: "Working", badge_style: :info).freeze
  OPEN_STATUSES = %w[pending running awaiting_confirmation].freeze

  def new
    prepare_form
  end

  def create
    prepare_form
    launch = PlaygroundLaunch.parse(params, catalog: @catalog)
    root = current_root_recording
    if root.nil?
      @error = "Pick a workspace first."
      render :new, status: :unprocessable_entity
      return
    end

    idempotency_key = "playground:#{SecureRandom.uuid}"
    PlaygroundRunJob.perform_later(
      idempotency_key,
      "playground-task:#{SecureRandom.uuid}",
      root.id,
      current_user.id,
      launch.agent_key,
      launch.agent_version,
      launch.goal,
      launch.context,
      pack_argument(launch.pack),
      extra_argument(launch.extra_skills)
    )
    redirect_to playground_run_path(idempotency_key)
  rescue PlaygroundLaunch::Error => error
    @error = error.message
    render :new, status: :unprocessable_entity
  end

  def show
    @run = find_run
    @error = show_error
    @subtitle = starting? ? "Starting." : nil
    @steps = show_steps
    @reply_text = reply_text
    @skill_names = skill_names
    @agent_name = agent_name
    @refresh = refresh?
    @finished = finished?
  end

  private

  def prepare_form
    @catalog = PlaygroundCatalog.entries
    @agent_options = @catalog.map { |entry| [ entry.name, entry.token ] }
    @form = Form.new(
      agent: params[:agent].presence || @catalog.first&.token,
      goal: params[:goal].to_s,
      context: params[:context].to_s,
      extra_skills: Array(params[:extra_skills]).flatten,
      pack: params[:pack]
    )
  end

  def pack_argument(pack)
    return if pack.nil?

    [ pack.key, pack.version ]
  end

  def extra_argument(choices)
    choices.map { |choice| [ choice.key, choice.version ] }
  end

  def find_run
    root = current_root_recording
    return if root.nil?

    RecordingStudioAgents::AgentRun.find_by(
      root_recording_id: root.id,
      idempotency_key: params[:idempotency_key]
    )
  end

  def show_error
    return "Pick a workspace first." if current_root_recording.nil?
    return if @run

    Rails.cache.read("playground:#{params[:idempotency_key]}:error")
  end

  def starting?
    @run.nil? && @error.blank?
  end

  def show_steps
    return [] if @run.nil? && @error.present?
    return [ WORKING ] if @run.nil?

    RecordingStudioAgents::Progress.for(@run)
  end

  def reply_text
    return if @run.nil? || @run.recording_studio_ai_run_id.blank?

    ai_run = RecordingStudioAI::Run.find_by(id: @run.recording_studio_ai_run_id)
    retained = RecordingStudioAgents::Ai.retained_output(ai_run: ai_run, initiator: current_user)
    retained&.dig(:text)
  end

  def agent_name
    return if @run.nil?

    entry = catalog_entries.find { |item| item.key == @run.agent_key && item.version == @run.agent_version }
    entry&.name
  end

  def catalog_entries
    @catalog_entries ||= PlaygroundCatalog.entries
  end

  def skill_names
    return [] if @run.nil?

    Array(@run.selected_skills_json).filter_map do |item|
      key = item["key"] || item[:key]
      version = item["version"] || item[:version]
      next if key.blank? || version.blank?

      RecordingStudioAgents.skills.fetch(key, version: version).name
    rescue RecordingStudioAgents::Error
      nil
    end
  end

  def refresh?
    return false if @error.present? && @run.nil?
    return true if @run.nil?

    %w[pending running].include?(@run.status)
  end

  def finished?
    @run.present? && OPEN_STATUSES.exclude?(@run.status)
  end
end
