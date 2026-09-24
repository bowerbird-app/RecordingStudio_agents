# frozen_string_literal: true

require "test_helper"

class PlaygroundStepsTest < ActiveSupport::TestCase
  Step = RecordingStudioAgents::Progress::Step

  test "each step shows what the agent was given and what it returned" do
    steps = [
      Step.new(kind: :knowledge, label: "Checked this workspace", status: :done, badge: "Done", badge_style: :success),
      Step.new(kind: :tool, label: "Find page", status: :done, badge: "Done", badge_style: :success),
      Step.new(kind: :finished, label: "Done", status: :done, badge: "Done", badge_style: :success)
    ]

    entries = PlaygroundSteps.build(
      steps,
      failure_message: nil,
      reply_text: "Found it.",
      instruction: "Find the staff handbook.",
      context: "{\"folder\":\"People\"}"
    )

    assert_equal [
      "playground-step-0",
      "playground-step-1",
      "playground-step-2",
      "playground-reply"
    ], entries.map(&:id)
    assert entries.all? { |entry| entry.given == "Find the staff handbook.\n\n{\"folder\":\"People\"}" }
    assert entries.all? { |entry| entry.returned == "Found it." }
  end

  test "a blank run has no collapses" do
    entries = PlaygroundSteps.build([], failure_message: nil, reply_text: nil, instruction: "")

    assert_empty entries
  end

  test "a failed run with no reply shows the failure" do
    steps = [
      Step.new(kind: :failed, label: "Did not finish", status: :failed, badge: "Failed", badge_style: :danger)
    ]

    entries = PlaygroundSteps.build(
      steps,
      failure_message: "The title was not saved.",
      reply_text: " ",
      instruction: "Rename the page."
    )

    assert_equal [ "playground-step-0" ], entries.map(&:id)
    assert_equal "Rename the page.", entries.first.given
    assert_equal "The title was not saved.", entries.first.returned
  end

  test "a run that is still going says so" do
    steps = [
      Step.new(kind: :running, label: "On it", status: :running, badge: "Working", badge_style: :info)
    ]

    entries = PlaygroundSteps.build(
      steps,
      failure_message: nil,
      reply_text: nil,
      instruction: "Find the staff handbook."
    )

    assert_equal "Still going.", entries.first.returned
  end

  test "the collapse renders given and returned" do
    step = PlaygroundSteps::Entry.new(
      id: "playground-step-1",
      title: "Find page",
      badge: "Done",
      badge_style: :success,
      given: "Find the staff handbook.",
      returned: "I found the page \"Staff handbook\"."
    )

    html = ApplicationController.render(partial: "playground/results", assigns: { steps: [ step ] })

    assert_includes html, "Given"
    assert_includes html, "Find the staff handbook."
    assert_includes html, "Returned"
    assert_includes html, "I found the page"
    assert_includes html, "playground-step-1-content"
  end
end
