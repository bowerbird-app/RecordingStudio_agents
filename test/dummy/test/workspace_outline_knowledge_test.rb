# frozen_string_literal: true

require "test_helper"

class WorkspaceOutlineKnowledgeTest < ActiveSupport::TestCase
  test "workspace outline cites the workspace root" do
    workspace = Workspace.create!(name: "Outline Source #{SecureRandom.hex(4)}")
    root = RecordingStudio.root_recording_for(workspace)
    definition = RecordingStudioAgents.knowledge.fetch(:workspace_outline, version: 1)
    context = RecordingStudioAgents::Knowledge::Context.new(
      task: RecordingStudioAgents::TaskInput.new(key: "outline", goal: "List pages."),
      root_recording: root,
      context_recording: nil,
      initiator: nil,
      executor: nil
    )

    entries = RecordingStudioAgents::Knowledge::Gatherer.load(definitions: [definition], context: context)

    assert_equal 1, entries.length
    assert_equal root, entries.first.source_recording
  end
end
