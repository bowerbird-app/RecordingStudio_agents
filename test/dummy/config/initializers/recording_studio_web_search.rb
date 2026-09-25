# frozen_string_literal: true

# Brave supplies web search. Cloud agents inject brave_search.
# The test suite stays offline so it never calls the provider.
RecordingStudio::WebSearch.configure do |config|
  config.provider = :brave
  config.brave_api_key = DummyAIProviderKeys.read("brave_search", offline: Rails.env.test?)
end
