# frozen_string_literal: true

module RecordingStudioAgents
  class Configuration
    attr_accessor :lease_seconds
    attr_reader :hooks, :profile, :controller_profile,
                :maximum_steps, :maximum_tool_actions, :maximum_reasoner_calls,
                :maximum_replans, :maximum_observation_calls, :maximum_runtime_seconds,
                :maximum_working_state_bytes,
                :finished_probability, :stuck_probability, :progress_probability,
                :needs_reasoning_probability, :choice_margin

    def initialize
      @lease_seconds = 300
      @profile = :medium
      @controller_profile = :low
      @maximum_steps = 80
      @maximum_tool_actions = 30
      @maximum_reasoner_calls = 8
      @maximum_replans = 3
      @maximum_observation_calls = 30
      @maximum_runtime_seconds = 1800
      @maximum_working_state_bytes = 12_000
      @finished_probability = 0.8
      @stuck_probability = 0.7
      @progress_probability = 0.55
      @needs_reasoning_probability = 0.6
      @choice_margin = 0.15
      @hooks = RecordingStudio::Hooks.new
    end

    def profile=(value)
      @profile = Profiles.coerce!(value)
    end

    def controller_profile=(value)
      @controller_profile = Profiles.coerce!(value)
    end

    def maximum_steps=(value)
      @maximum_steps = positive_integer(value, "maximum_steps")
    end

    def maximum_tool_actions=(value)
      @maximum_tool_actions = positive_integer(value, "maximum_tool_actions")
    end

    def maximum_reasoner_calls=(value)
      @maximum_reasoner_calls = positive_integer(value, "maximum_reasoner_calls")
    end

    def maximum_replans=(value)
      @maximum_replans = positive_integer(value, "maximum_replans")
    end

    def maximum_observation_calls=(value)
      @maximum_observation_calls = positive_integer(value, "maximum_observation_calls")
    end

    def maximum_runtime_seconds=(value)
      @maximum_runtime_seconds = positive_integer(value, "maximum_runtime_seconds")
    end

    def maximum_working_state_bytes=(value)
      @maximum_working_state_bytes = positive_integer(value, "maximum_working_state_bytes")
    end

    def finished_probability=(value)
      @finished_probability = probability(value, "finished_probability")
    end

    def stuck_probability=(value)
      @stuck_probability = probability(value, "stuck_probability")
    end

    def progress_probability=(value)
      @progress_probability = probability(value, "progress_probability")
    end

    def needs_reasoning_probability=(value)
      @needs_reasoning_probability = probability(value, "needs_reasoning_probability")
    end

    def choice_margin=(value)
      @choice_margin = probability(value, "choice_margin")
    end

    def to_h
      {
        lease_seconds: lease_seconds,
        profile: profile,
        controller_profile: controller_profile,
        maximum_steps: maximum_steps,
        maximum_tool_actions: maximum_tool_actions,
        maximum_reasoner_calls: maximum_reasoner_calls,
        maximum_replans: maximum_replans,
        maximum_observation_calls: maximum_observation_calls,
        maximum_runtime_seconds: maximum_runtime_seconds,
        maximum_working_state_bytes: maximum_working_state_bytes,
        finished_probability: finished_probability,
        stuck_probability: stuck_probability,
        progress_probability: progress_probability,
        needs_reasoning_probability: needs_reasoning_probability,
        choice_margin: choice_margin,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |key, value|
        setter = "#{key}="
        public_send(setter, value) if respond_to?(setter)
      end
    end

    private

    def positive_integer(value, name)
      number = Integer(value)
      return number if number.positive?

      raise ContractError, "#{name} must be a positive integer"
    rescue ArgumentError, TypeError
      raise ContractError, "#{name} must be a positive integer"
    end

    def probability(value, name)
      number = Float(value)
      return number if number.between?(0.0, 1.0)

      raise ContractError, "#{name} must be between 0 and 1"
    rescue ArgumentError, TypeError
      raise ContractError, "#{name} must be between 0 and 1"
    end
  end
end
