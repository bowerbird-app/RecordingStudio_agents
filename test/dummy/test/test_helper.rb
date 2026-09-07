# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
ENV.delete("OPENAI_API_KEY")
ENV.delete("GEMINI_API_KEY")

require_relative "../config/environment"
require "rails/test_help"
require_relative "support/accessible_test_helpers"

class ActionDispatch::IntegrationTest
  include AccessibleTestHelpers
end
