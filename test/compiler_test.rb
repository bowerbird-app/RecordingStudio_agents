# frozen_string_literal: true

require "test_helper"

class CompilerTest < Minitest::Test
  include RegistryHelpers

  def test_compile_requires_skill_tools_on_agent_allowlist
    register_ai_tool(:find_page)
    RecordingStudioAgents.skills.register(
      key: :lookup,
      version: 1,
      name: "Lookup",
      description: "Find things",
      instructions: "Use find_page.",
      required_tools: { find_page: 1 }
    )
    RecordingStudioAgents.agents.register(
      key: :librarian,
      version: 1,
      name: "Librarian",
      description: "Finds pages",
      instructions: "Find the page.",
      skills: { lookup: 1 }
    )

    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents.finalize!
    end
    assert_match(/not on agent librarian/, error.message)
  end

  def test_compile_requires_registered_ai_tool
    RecordingStudioAgents.agents.register(
      key: :librarian,
      version: 1,
      name: "Librarian",
      description: "Finds pages",
      instructions: "Find the page.",
      tools: { find_page: 1 }
    )

    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents.finalize!
    end
    assert_match(/AI tool find_page/, error.message)
  end

  def test_compile_pins_exact_versions
    register_ai_tool(:find_page)
    RecordingStudioAgents.skills.register(
      key: :lookup,
      version: 1,
      name: "Lookup",
      description: "Find things",
      instructions: "Use find_page.",
      required_tools: { find_page: 1 }
    )
    RecordingStudioAgents.agents.register(
      key: :librarian,
      version: 1,
      name: "Librarian",
      description: "Finds pages",
      instructions: "Find the page.",
      skills: { lookup: 1 },
      tools: { find_page: 1 }
    )

    program = RecordingStudioAgents::Programs::Compiler.compile(
      definition: RecordingStudioAgents.agents.fetch(:librarian, version: 1)
    )
    assert program.digest.match?(/\A[0-9a-f]{64}\z/)
    assert_equal 2, program.instruction_blocks.length
  end

  def test_compile_requires_registered_knowledge
    register_ai_tool(:find_page)
    RecordingStudioAgents.agents.register(
      key: :librarian,
      version: 1,
      name: "Librarian",
      description: "Finds pages",
      instructions: "Find the page.",
      tools: { find_page: 1 },
      knowledge: { workspace_outline: 1 }
    )

    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents.finalize!
    end
    assert_match(/workspace_outline/, error.message)
  end

  def test_compose_includes_knowledge_and_handoff_instructions
    register_ai_tool(:find_page)
    RecordingStudioAgents.knowledge.register(
      key: :outline,
      version: 1,
      name: "Outline",
      description: "Pages",
      loader: lambda { |_context|
        [
          RecordingStudioAgents::Knowledge::Entry.new(
            key: "outline",
            title: "Outline",
            content: "Getting Started"
          )
        ]
      }
    )
    RecordingStudioAgents.agents.register(
      key: :reviewer,
      version: 1,
      name: "Reviewer",
      description: "Reviews",
      instructions: "Review."
    )
    RecordingStudioAgents.agents.register(
      key: :librarian,
      version: 1,
      name: "Librarian",
      description: "Finds pages",
      instructions: "Find the page.",
      tools: { find_page: 1 },
      knowledge: { outline: 1 },
      handoffs: { reviewer: 1 }
    )

    program = RecordingStudioAgents::Programs::Compiler.compile(
      definition: RecordingStudioAgents.agents.fetch(:librarian, version: 1)
    )
    request = RecordingStudioAgents::Execution::Request.parse(
      task: RecordingStudioAgents::TaskInput.new(key: "t", goal: "Find it."),
      root_recording: Struct.new(:id).new(1),
      initiator: Struct.new(:id).new(2),
      execution_source: :job,
      idempotency_key: "k"
    )
    invocation = program.compose(task: request.task_input, request: request, run: Struct.new(:id).new(9))

    assert_match(/Application data/, invocation.system_instruction)
    assert_match(/Getting Started/, invocation.system_instruction)
    assert_match(/Allowed handoff targets: reviewer v1/, invocation.system_instruction)
    assert program.allows_handoff?(:reviewer, 1)
    refute program.allows_handoff?(:stranger, 1)
    assert_includes program.effective_tool_references.map(&:key), "recording_studio_agents_request_handoff"
  end
end
