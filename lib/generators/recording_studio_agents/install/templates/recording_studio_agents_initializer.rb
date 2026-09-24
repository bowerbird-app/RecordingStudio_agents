# frozen_string_literal: true

RecordingStudioAgents.configure do |config|
  config.lease_seconds = 300
  config.maximum_steps = 80
  config.maximum_tool_actions = 30
  config.maximum_reasoner_calls = 8
  config.maximum_replans = 3
  config.maximum_observation_calls = 30
  config.maximum_runtime_seconds = 1800
end
