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

  def test_default_compile_omits_optional_skills
    register_support_clerk
    program = RecordingStudioAgents::Programs::Compiler.compile(
      definition: RecordingStudioAgents.agents.fetch(:support_clerk, version: 1)
    )

    texts = program.instruction_blocks.map(&:text)
    assert(texts.any? { |text| text.include?("Keep a steady voice") })
    refute(texts.any? { |text| text.include?("refund window") })
    refute(texts.any? { |text| text.include?("reset link") })
    refute_includes program.tool_references.map(&:key), "lookup_invoice"
  end

  def test_pack_compile_includes_pack_skills_and_their_tools
    register_support_clerk
    definition = RecordingStudioAgents.agents.fetch(:support_clerk, version: 1)
    selection = RecordingStudioAgents::SkillSelection.parse(definition: definition, pack: :billing_tickets)
    program = RecordingStudioAgents::Programs::Compiler.compile(definition: definition, selection: selection)

    texts = program.instruction_blocks.map(&:text)
    assert(texts.any? { |text| text.include?("refund window") })
    refute(texts.any? { |text| text.include?("reset link") })
    assert_includes program.tool_references.map(&:key), "lookup_invoice"
  end

  def test_extra_skills_compile_includes_named_optional_skill
    register_support_clerk
    definition = RecordingStudioAgents.agents.fetch(:support_clerk, version: 1)
    selection = RecordingStudioAgents::SkillSelection.parse(
      definition: definition,
      extra_skills: { login_help: 1 }
    )
    program = RecordingStudioAgents::Programs::Compiler.compile(definition: definition, selection: selection)

    texts = program.instruction_blocks.map(&:text)
    assert(texts.any? { |text| text.include?("reset link") })
    refute(texts.any? { |text| text.include?("refund window") })
  end

  def test_unknown_extra_skill_is_rejected
    register_support_clerk
    definition = RecordingStudioAgents.agents.fetch(:support_clerk, version: 1)
    error = assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents::SkillSelection.parse(
        definition: definition,
        extra_skills: { page_lookup: 1 }
      )
    end
    assert_match(/not an optional skill/, error.message)
  end

  def test_unknown_pack_is_rejected
    register_support_clerk
    definition = RecordingStudioAgents.agents.fetch(:support_clerk, version: 1)
    error = assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents::SkillSelection.parse(definition: definition, pack: :missing_pack)
    end
    assert_match(/does not allow pack/, error.message)
  end

  def test_pack_skills_must_be_optional_on_the_agent
    register_ai_tool(:lookup_invoice)
    RecordingStudioAgents.skills.register(
      key: :secret_help,
      version: 1,
      name: "Secret help",
      description: "Not optional",
      instructions: "Do not load this by default."
    )
    RecordingStudioAgents.skill_packs.register(
      key: :secret_pack,
      version: 1,
      name: "Secret pack",
      description: "Includes a skill the agent did not allow.",
      skills: { secret_help: 1 }
    )
    RecordingStudioAgents.agents.register(
      key: :broken_clerk,
      version: 1,
      name: "Broken clerk",
      description: "Pack is not a subset.",
      instructions: "Fail at compile.",
      packs: { secret_pack: 1 }
    )

    error = assert_raises(RecordingStudioAgents::ConfigurationError) do
      RecordingStudioAgents.finalize!
    end
    assert_match(/not optional on agent broken_clerk/, error.message)
  end

  def test_pack_hash_must_name_one_pack
    register_support_clerk
    definition = RecordingStudioAgents.agents.fetch(:support_clerk, version: 1)
    error = assert_raises(RecordingStudioAgents::ContractError) do
      RecordingStudioAgents::SkillSelection.parse(
        definition: definition,
        pack: { billing_tickets: 1, other: 1 }
      )
    end
    assert_match(/one pack/, error.message)
  end

  def test_pack_and_extra_skills_combine
    register_support_clerk
    definition = RecordingStudioAgents.agents.fetch(:support_clerk, version: 1)
    selection = RecordingStudioAgents::SkillSelection.parse(
      definition: definition,
      pack: :billing_tickets,
      extra_skills: { login_help: 1 }
    )
    program = RecordingStudioAgents::Programs::Compiler.compile(definition: definition, selection: selection)
    texts = program.instruction_blocks.map(&:text)

    assert(texts.any? { |text| text.include?("refund window") })
    assert(texts.any? { |text| text.include?("reset link") })
  end
end
