# frozen_string_literal: true

require "test_helper"

class McpCopyTest < Minitest::Test
  NAMES = %w[
    list_agent_chats create_agent_chat read_agent_chat append_agent_chat
    list_agent_items read_agent_item
  ].freeze
  OLD_NAMES = %w[
    agent_chats_list agent_chats_create agent_chats_read agent_chats_append
    agent_items_list agent_items_read
  ].freeze
  GENERIC_NAMES = %w[list show create update delete capability_action describe].freeze
  ROLE_WORDS = ["view access", "edit access", "admin", ":view", ":edit", "permission", " role"].freeze

  def test_tool_names_are_the_named_tools
    assert_equal NAMES, RecordingStudioAgents::McpCopy.tool_names
    OLD_NAMES.each { |name| refute_includes RecordingStudioAgents::McpCopy.tool_names, name }
    GENERIC_NAMES.each { |name| refute_includes RecordingStudioAgents::McpCopy.tool_names, name }
    NAMES.each { |name| refute_includes name, "::" }
  end

  def test_register_is_a_no_op_without_mcp
    refute defined?(RecordingStudioMcp)
    refute RecordingStudioAgents::McpCopy.mcp_available?

    assert_nil RecordingStudioAgents::McpCopy.register!

    refute defined?(RecordingStudioMcp)
  end

  def test_register_declares_each_named_tool_on_its_endpoint
    fake = RecordingMcp.new

    RecordingStudioAgents::McpCopy.stub(:mcp_available?, true) do
      RecordingStudioAgents::McpCopy.stub(:mcp, fake) do
        RecordingStudioAgents::McpCopy.register!
        RecordingStudioAgents::McpCopy.register!
      end
    end

    assert_equal NAMES, fake.tools.keys
    NAMES.each do |name|
      tool = fake.tools.fetch(name)
      assert_equal name.to_sym, tool[:endpoint]
      refute tool.key?(:operation)
      refute tool.key?(:action)
      refute tool.key?(:type)
      copy = RecordingStudioAgents::McpCopy::Copy
      api = RecordingStudioAgents::Api::ToolCopy
      assert_equal copy::TITLES.fetch(name), tool[:title]
      assert_equal copy.description(name), tool[:description]
      assert_equal copy::OUTPUTS.fetch(name), tool[:output]
      refute_equal api.description(name), tool[:description]
      refute_includes api.description(name), name
      assert(tool[:input].values.all? { |field| field.fetch(:description).present? })
      assert_includes tool[:description], "chat"
      ROLE_WORDS.each { |phrase| refute_includes tool[:description].downcase, phrase, name }
    end
    assert_includes fake.tools.fetch("create_agent_chat")[:description], "idempotency_key"
    assert_includes fake.tools.fetch("append_agent_chat")[:description], "idempotency_key"
  end

  def test_engine_registers_tools_without_a_gemspec_dependency
    gemspec = File.read(File.expand_path("../recording_studio_agents.gemspec", __dir__))
    engine = File.read(File.expand_path("../lib/recording_studio_agents/engine.rb", __dir__))

    refute_includes gemspec, "recording_studio_mcp"
    assert_includes engine, 'require_relative "mcp_copy"'
    assert_includes engine, "McpCopy.register!"
  end

  def test_own_tools_stay_out_of_chat_tools
    tools = RecordingStudioAgents::Mcp::ChatTools

    RecordingStudioAgents::McpCopy.tool_names.each do |name|
      assert tools.self_tool?(name), name
    end
    refute tools.self_tool?("update")
    refute tools.self_tool?("list")
  end

  class RecordingMcp
    attr_reader :tools

    def initialize
      @tools = {}
    end

    def register_tool(**registration)
      tools[registration.fetch(:name)] = registration
    end
  end
end
