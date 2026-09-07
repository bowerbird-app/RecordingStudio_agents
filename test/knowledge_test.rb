# frozen_string_literal: true

require "test_helper"

class KnowledgeTest < Minitest::Test
  include RegistryHelpers

  FakeRecording = Struct.new(:id, :root_recording_id)

  def test_rejects_entries_outside_root
    root = FakeRecording.new(1, 1)
    outsider = FakeRecording.new(9, 2)
    context = RecordingStudioAgents::Knowledge::Context.new(
      task: RecordingStudioAgents::TaskInput.new(key: "t", goal: "g"),
      root_recording: root,
      context_recording: nil,
      initiator: nil,
      executor: nil
    )
    definition = RecordingStudioAgents::Knowledge::Definition.new(
      key: :outline,
      version: 1,
      name: "Outline",
      description: "Pages",
      loader: lambda { |_context|
        [
          RecordingStudioAgents::Knowledge::Entry.new(
            key: "other",
            title: "Other",
            content: "secret",
            source_recording: outsider
          )
        ]
      }
    )

    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents::Knowledge::Gatherer.load(definitions: [definition], context: context)
    end
    assert_match(/outside the task root/, error.message)
  end

  def test_allows_entries_without_source_recording
    root = FakeRecording.new(1, 1)
    context = RecordingStudioAgents::Knowledge::Context.new(
      task: RecordingStudioAgents::TaskInput.new(key: "t", goal: "g"),
      root_recording: root,
      context_recording: nil,
      initiator: nil,
      executor: nil
    )
    definition = RecordingStudioAgents::Knowledge::Definition.new(
      key: :catalog,
      version: 1,
      name: "Catalog",
      description: "Host catalog",
      loader: lambda { |_context|
        [
          RecordingStudioAgents::Knowledge::Entry.new(
            key: "catalog",
            title: "Catalog",
            content: "a,b,c"
          )
        ]
      }
    )

    entries = RecordingStudioAgents::Knowledge::Gatherer.load(definitions: [definition], context: context)
    assert_equal 1, entries.length
  end

  def test_enforces_byte_cap
    root = FakeRecording.new(1, 1)
    context = RecordingStudioAgents::Knowledge::Context.new(
      task: RecordingStudioAgents::TaskInput.new(key: "t", goal: "g"),
      root_recording: root,
      context_recording: nil,
      initiator: nil,
      executor: nil
    )
    definition = RecordingStudioAgents::Knowledge::Definition.new(
      key: :huge,
      version: 1,
      name: "Huge",
      description: "Too big",
      loader: lambda { |_context|
        [
          RecordingStudioAgents::Knowledge::Entry.new(
            key: "huge",
            title: "Huge",
            content: "x" * (RecordingStudioAgents::Knowledge::MAXIMUM_BYTES + 1)
          )
        ]
      }
    )

    assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents::Knowledge::Gatherer.load(definitions: [definition], context: context)
    end
  end

  def test_enforces_entry_cap
    root = FakeRecording.new(1, 1)
    context = RecordingStudioAgents::Knowledge::Context.new(
      task: RecordingStudioAgents::TaskInput.new(key: "t", goal: "g"),
      root_recording: root,
      context_recording: nil,
      initiator: nil,
      executor: nil
    )
    definition = RecordingStudioAgents::Knowledge::Definition.new(
      key: :many,
      version: 1,
      name: "Many",
      description: "Too many",
      loader: lambda { |_context|
        (RecordingStudioAgents::Knowledge::MAXIMUM_ENTRIES + 1).times.map do |index|
          RecordingStudioAgents::Knowledge::Entry.new(
            key: "item_#{index}",
            title: "Item #{index}",
            content: "x"
          )
        end
      }
    )

    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents::Knowledge::Gatherer.load(definitions: [definition], context: context)
    end
    assert_match(/maximum is #{RecordingStudioAgents::Knowledge::MAXIMUM_ENTRIES}/, error.message)
  end

  def test_times_out_slow_loader
    root = FakeRecording.new(1, 1)
    context = RecordingStudioAgents::Knowledge::Context.new(
      task: RecordingStudioAgents::TaskInput.new(key: "t", goal: "g"),
      root_recording: root,
      context_recording: nil,
      initiator: nil,
      executor: nil
    )
    definition = RecordingStudioAgents::Knowledge::Definition.new(
      key: :slow,
      version: 1,
      name: "Slow",
      description: "Hangs",
      loader: ->(_context) { [] }
    )

    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      Timeout.stub(:timeout, ->(*) { raise Timeout::Error }) do
        RecordingStudioAgents::Knowledge::Gatherer.load(definitions: [definition], context: context)
      end
    end
    assert_match(/timed out/, error.message)
  end

  def test_allows_source_inside_root
    root = FakeRecording.new(1, 1)
    child = FakeRecording.new(2, 1)
    context = RecordingStudioAgents::Knowledge::Context.new(
      task: RecordingStudioAgents::TaskInput.new(key: "t", goal: "g"),
      root_recording: root,
      context_recording: nil,
      initiator: nil,
      executor: nil
    )
    definition = RecordingStudioAgents::Knowledge::Definition.new(
      key: :inside,
      version: 1,
      name: "Inside",
      description: "Child page",
      loader: lambda { |_context|
        [
          RecordingStudioAgents::Knowledge::Entry.new(
            key: "page",
            title: "Page",
            content: "hello",
            source_recording: child
          )
        ]
      }
    )

    entries = RecordingStudioAgents::Knowledge::Gatherer.load(definitions: [definition], context: context)
    assert_equal 1, entries.length
  end

  def test_loader_must_return_entries
    root = FakeRecording.new(1, 1)
    context = RecordingStudioAgents::Knowledge::Context.new(
      task: RecordingStudioAgents::TaskInput.new(key: "t", goal: "g"),
      root_recording: root,
      context_recording: nil,
      initiator: nil,
      executor: nil
    )
    definition = RecordingStudioAgents::Knowledge::Definition.new(
      key: :bad,
      version: 1,
      name: "Bad",
      description: "Wrong shape",
      loader: ->(_context) { { "title" => "nope" } }
    )

    assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents::Knowledge::Gatherer.load(definitions: [definition], context: context)
    end
  end
end
