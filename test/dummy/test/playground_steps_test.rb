# frozen_string_literal: true

require "test_helper"

class PlaygroundStepsTest < ActiveSupport::TestCase
  Step = RecordingStudioAgents::Progress::Step
  Invocation = Struct.new(:error_message, :result_summary, :metadata, keyword_init: true)

  test "builds a closed step for each progress row and a reply collapse" do
    steps = [
      Step.new(kind: :knowledge, label: "Checked this workspace", status: :done, badge: "Done", badge_style: :success),
      Step.new(kind: :tool, label: "Find page", status: :done, badge: "Done", badge_style: :success),
      Step.new(kind: :finished, label: "Done", status: :done, badge: "Done", badge_style: :success)
    ]

    entries = PlaygroundSteps.build(
      steps,
      [ Invocation.new(result_summary: "Getting Started is in Product Docs.") ],
      failure_message: nil,
      reply_text: "Found it."
    )

    assert_equal [
      [ "playground-step-0", "Checked this workspace", "Done", "Looked through this workspace." ],
      [ "playground-step-1", "Find page", "Done", "Getting Started is in Product Docs." ],
      [ "playground-step-2", "Wrapped up", "Done", "The run finished." ],
      [ "playground-reply", "Reply", "Done", "Found it." ]
    ], entries.map { |entry| [ entry.id, entry.title, entry.badge, entry.body ] }
  end

  test "a blank run has no reply collapse" do
    entries = PlaygroundSteps.build([], [], failure_message: nil, reply_text: nil)

    assert_empty entries
  end

  test "a waiting tool and a failed run keep their own detail" do
    steps = [
      Step.new(kind: :tool, label: "Retitle page", status: :waiting, badge: "Waiting", badge_style: :warning),
      Step.new(kind: :failed, label: "Did not finish", status: :failed, badge: "Failed", badge_style: :danger)
    ]

    entries = PlaygroundSteps.build(
      steps,
      [ Invocation.new(error_message: "Needs a yes.") ],
      failure_message: "The title was not saved.",
      reply_text: " "
    )

    assert_equal "Waiting for a yes before using Retitle page.", entries.first.body
    assert_equal "The title was not saved.", entries.second.body
    assert_equal 2, entries.length
  end

  test "a machine summary does not replace the tool sentence" do
    steps = [
      Step.new(kind: :tool, label: "Find page", status: :done, badge: "Done", badge_style: :success)
    ]
    summary = "{\"type\":\"Hash\",\"byte_size\":116}"

    entries = PlaygroundSteps.build(
      steps,
      [ Invocation.new(result_summary: summary) ],
      failure_message: nil,
      reply_text: nil
    )

    assert_equal "Used Find page.", entries.first.body
    assert_nil entries.first.arguments_text
  end

  test "a tool step shows the arguments that were passed in" do
    steps = [
      Step.new(kind: :tool, label: "Find page", status: :done, badge: "Done", badge_style: :success)
    ]

    entries = PlaygroundSteps.build(
      steps,
      [ Invocation.new(metadata: { "arguments" => { "title" => "Staff handbook" } }) ],
      failure_message: nil,
      reply_text: nil
    )

    assert_equal "Used Find page.", entries.first.body
    assert_equal "{\n  \"title\": \"Staff handbook\"\n}", entries.first.arguments_text
  end

  test "the collapse renders passed-in arguments" do
    step = PlaygroundSteps::Entry.new(
      id: "playground-step-1",
      title: "Find page",
      badge: "Done",
      badge_style: :success,
      body: "Used Find page.",
      arguments_text: "{\n  \"title\": \"Staff handbook\"\n}"
    )

    html = ApplicationController.render(partial: "playground/results", assigns: { steps: [ step ] })

    assert_includes html, "Passed in"
    assert_includes html, "Staff handbook"
    assert_includes html, "playground-step-1-content"
  end

  test "a tool with no summary says which tool ran" do
    steps = [
      Step.new(kind: :tool, label: "List pages", status: :running, badge: "Working", badge_style: :info)
    ]

    entries = PlaygroundSteps.build(steps, [ Invocation.new ], failure_message: nil, reply_text: nil)

    assert_equal "Used List pages.", entries.first.body
    assert_equal "Working", entries.first.badge
  end
end
