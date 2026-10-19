# frozen_string_literal: true

require "test_helper"

class FilterInstructionsTest < Minitest::Test
  def test_apply_appends_instructions_once
    list = [:passw]
    app = Struct.new(:config).new(Struct.new(:filter_parameters).new(list))

    RecordingStudioAgents::FilterInstructions.apply(app)
    RecordingStudioAgents::FilterInstructions.apply(app)

    assert_equal %i[passw instructions], list
  end

  def test_apply_leaves_an_existing_instructions_entry
    list = ["instructions"]
    app = Struct.new(:config).new(Struct.new(:filter_parameters).new(list))

    RecordingStudioAgents::FilterInstructions.apply(app)

    assert_equal ["instructions"], list
  end
end
