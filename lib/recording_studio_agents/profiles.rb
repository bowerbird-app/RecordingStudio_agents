# frozen_string_literal: true

module RecordingStudioAgents
  # Cost and quality tier for a generate call. The host maps each name to
  # provider and model candidates in Recording Studio AI.
  module Profiles
    NAMES = %i[low medium high].freeze
    LABELS = { low: "Low", medium: "Medium", high: "High" }.freeze

    module_function

    def label(name)
      LABELS.fetch(coerce!(name))
    end

    def resolve(run_profile, agent_profile)
      choice = blank?(run_profile) ? agent_profile : run_profile
      choice = RecordingStudioAgents.configuration.profile if blank?(choice)
      coerce!(choice)
    end

    def coerce!(value)
      text = value.to_s.strip
      symbol = text.downcase.to_sym
      return symbol if NAMES.include?(symbol) && text.match?(/\A[a-zA-Z]+\z/)

      raise ContractError, "profile must be one of: low, medium, high"
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
