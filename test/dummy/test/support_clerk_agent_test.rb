# frozen_string_literal: true

require "test_helper"

class SupportClerkAgentTest < ActiveSupport::TestCase
  include AccessibleTestHelpers

  setup do
    @user = User.find_or_create_by!(email: "support-clerk@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    @workspace = Workspace.find_or_create_by!(name: "Support Clerk")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_accessible!(recording: @root, actor: @user)
  end

  test "default run keeps the voice skill and omits billing help" do
    result, captured = stub_generate do
      RecordingStudioAgents.agent(:support_clerk, version: 1).run(
        task: task_input,
        root_recording: @root,
        initiator: @user,
        execution_source: :job,
        idempotency_key: "dummy-support-default"
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_match(/Keep a steady voice/, captured[:system_instruction])
    refute_match(/refund window/, captured[:system_instruction])
    refute_match(/reset link/, captured[:system_instruction])
    assert_equal [], result.run.selected_skills_json
  end

  test "pack run loads billing help and not login help" do
    result, captured = stub_generate do
      RecordingStudioAgents.agent(:support_clerk, version: 1).run(
        task: task_input,
        root_recording: @root,
        initiator: @user,
        execution_source: :job,
        idempotency_key: "dummy-support-billing",
        pack: :billing_tickets
      )
    end

    assert_instance_of RecordingStudioAgents::Results::Completed, result
    assert_match(/refund window/, captured[:system_instruction])
    refute_match(/reset link/, captured[:system_instruction])
    assert_equal [{ "key" => "billing_help", "version" => 1 }], result.run.selected_skills_json
    assert_equal "billing_tickets", result.run.skill_pack_key
  end

  private

  def stub_generate
    captured = {}
    response = generation_response
    result = nil
    RecordingStudioAI.stub(:generate, lambda { |**kwargs|
      captured.clear
      kwargs.each { |key, value| captured[key] = value }
      response
    }) do
      result = yield
    end
    [result, captured]
  end

  def task_input
    RecordingStudioAgents::TaskInput.new(
      key: "support:#{@root.id}:#{SecureRandom.uuid}",
      goal: "Help with this ticket.",
      context: {}
    )
  end

  def generation_response
    RecordingStudioAI::Contracts::GenerationResponse.new(
      operation: "generation",
      purpose: "agent_support_clerk",
      text: "Here is the answer.",
      run: Struct.new(:id, :status).new(SecureRandom.random_number(2**31 - 1) + 1, "completed")
    )
  end
end
