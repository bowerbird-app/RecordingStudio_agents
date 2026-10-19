# frozen_string_literal: true

require "test_helper"

class FilterInstructionsTest < Minitest::Test
  def test_apply_appends_the_exact_instructions_key_once
    list = [:passw]
    app = Struct.new(:config).new(Struct.new(:filter_parameters).new(list))

    RecordingStudioAgents::FilterInstructions.apply(app)
    RecordingStudioAgents::FilterInstructions.apply(app)

    assert_equal [:passw, RecordingStudioAgents::FilterInstructions::PARAMETER], list
    filtered = ActiveSupport::ParameterFilter.new(list)
    assert_equal "[FILTERED]", filtered.filter(instructions: "secret")[:instructions]
    assert_equal "keep", filtered.filter(shipping_instructions: "keep")[:shipping_instructions]
  end
end
