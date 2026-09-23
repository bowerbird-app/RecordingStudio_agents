# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

ENV.delete("OPENAI_API_KEY")
ENV.delete("GEMINI_API_KEY")
ENV.delete("GOOGLE_AI_STUDIO")
ENV.delete("google_ai_studio")
ENV.delete("TYPESAFE_API_KEY")
ENV.delete("TYPESAFE")
ENV.delete("typesafe")

require_relative "simplecov_helper"
require "minitest/autorun"
begin
  require "minitest/mock"
rescue LoadError
  nil
end
require "rails"
require "active_support/time"
Time.zone ||= "UTC"
require "recording_studio_agents"
require_relative "support/registry_helpers"
require_relative "support/persistence"
