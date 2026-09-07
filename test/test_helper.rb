# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

ENV.delete("OPENAI_API_KEY")
ENV.delete("GEMINI_API_KEY")

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
