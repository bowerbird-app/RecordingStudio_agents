# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"
RecordingStudioAgents.configuration.allow_chat_tools_in_transaction = true

module AgentsInstructionHelper
  def with_safety_preamble(body)
    preamble = RecordingStudioAgents::Sessions::InstructionsText::PREAMBLE
    text = body.to_s.strip
    return preamble if text.empty?

    "#{preamble}\n\n#{text}"
  end
end

ActiveSupport::TestCase.include(AgentsInstructionHelper)
