# frozen_string_literal: true

class PlaygroundController < ApplicationController
  Form = Data.define(:agent, :goal, :context, :skills, :tools)
  StepLine = Data.define(:label, :badge, :badge_style)
  WORKING = StepLine.new(label: "On it", badge: "Working", badge_style: :info).freeze
  OPEN_STATUSES = %w[pending running awaiting_confirmation].freeze

  before_action :prepare_page

  def new
    @form = form_from_params
  end

  def create
    @form = form_from_params
    launch = PlaygroundLaunch.parse(params, catalog: @catalog)
    root = current_root_recording
    if root.nil?
      @error = "Pick a workspace first."
      render :new, status: :unprocessable_entity
      return
    end

    idempotency_key = "playground:#{SecureRandom.uuid}"
    remember_form(idempotency_key)
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
      pair_argument(launch.extra_skills),
      pair_argument(launch.skills),
      pair_argument(launch.tools)
    )
    redirect_to playground_run_path(idempotency_key)
  rescue PlaygroundLaunch::Error => error
    @error = error.message
    render :new, status: :unprocessable_entity
  end

  def show
    @run = find_run
    @error = show_error
    @form = remembered_form || form_from_run || form_from_params
    @starting = starting?
    @steps = show_steps
    @reply_text = reply_text
    @skill_names = skill_names
    @agent_name = agent_name
    @refresh = refresh?
    @finished = finished?
  end

  private

  def prepare_page
    @catalog = PlaygroundCatalog.entries
    @skill_options = PlaygroundCatalog.skills
    @agent_options = @catalog.map { |entry| [ entry.name, entry.token ] }
    @steps = []
    @skill_names = []
    @starting = false
    @finished = false
    @refresh = false
  end

  def form_from_params
    agent = params[:agent].presence || @catalog.first&.token
    Form.new(
      agent: agent,
      goal: params[:goal].to_s,
      context: params[:context].to_s,
      skills: submitted_or_default(:skills, agent, :required_skills),
      tools: submitted_or_default(:tools, agent, :tools)
    )
  end

  def submitted_or_default(key, agent, list_name)
    return tokens_for(agent, list_name) if params[:choices].blank?

    Array(params[key]).flatten.compact_blank
  end

  def tokens_for(agent, list_name)
    entry = @catalog.find { |item| item.token == agent }
    return [] unless entry

    entry.public_send(list_name).map(&:token)
  end

  def remembered_form
    payload = Rails.cache.read("playground:#{params[:idempotency_key]}:form")
    payload ||= session_form
    return if payload.blank?

    agent = payload["agent"]
    Form.new(
      agent: agent,
      goal: payload["goal"].to_s,
      context: payload["context"].to_s,
      skills: payload["skills"] || tokens_for(agent, :required_skills),
      tools: payload["tools"] || tokens_for(agent, :tools)
    )
  end

  def form_from_run
    return if @run.nil?

    agent = "#{@run.agent_key}@#{@run.agent_version}"
    stored = Array(@run.selected_skills_json).filter_map { |item| token_from(item) }
    Form.new(
      agent: agent,
      goal: @run.task.goal,
      context: "",
      skills: stored.presence || tokens_for(agent, :required_skills),
      tools: tokens_for(agent, :tools)
    )
  end

  def token_from(item)
    key = item["key"] || item[:key]
    version = item["version"] || item[:version]
    return if key.blank? || version.blank?

    "#{key}@#{version}"
  end

  def remember_form(idempotency_key)
    payload = {
      "idempotency_key" => idempotency_key,
      "agent" => @form.agent,
      "goal" => @form.goal,
      "context" => @form.context,
      "skills" => params[:choices].present? ? @form.skills : nil,
      "tools" => params[:choices].present? ? @form.tools : nil
    }
    Rails.cache.write("playground:#{idempotency_key}:form", payload)
    session[:playground_form] = payload
  end

  def session_form
    payload = session[:playground_form]
    return if payload.blank? || payload["idempotency_key"] != params[:idempotency_key]

    payload
  end

  def pack_argument(pack)
    return if pack.nil?

    [ pack.key, pack.version ]
  end

  def pair_argument(choices)
    return if choices.nil?

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

    entry = @catalog.find { |item| item.key == @run.agent_key && item.version == @run.agent_version }
    entry&.name
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
