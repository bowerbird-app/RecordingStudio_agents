# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class PlaygroundTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @user = User.find_or_create_by!(email: "playground@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    @workspace = Workspace.find_or_create_by!(name: "Playground")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_accessible!(recording: @root, actor: @user)
    sign_in @user
    switch_to_root!(@root)
  end

  test "playground lists registered agents and a sidebar link" do
    get "/playground"

    assert_response :success
    assert RecordingStudioAI.configuration.retain_responses
    assert_includes response.body, "Playground"
    assert_includes response.body, "Try an agent on this workspace and watch the steps."
    assert_includes response.body, "md:grid-cols-2"
    assert_select "[data-controller='flat-pack--collapse']", count: 0
    refute_includes response.body, "Run it to see the steps."
    assert_select "textarea[name='goal']"
    assert_select "form .grid.grid-cols-1.gap-4"
    assert_select "[data-playground-skills] [data-flat-pack--select-searchable-value='true']"
    assert_select "[data-playground-skills] input[placeholder='Search...']"
    assert_select "[data-playground-skills] input[name='skills[]'][value='page_lookup@1']"
    assert_select "select[name='skills[]']", count: 0
    assert_select "[data-playground-tools='page_librarian@1']:not([disabled]) [data-flat-pack--select-searchable-value='true']"
    assert_select "[data-playground-tools='page_librarian@1'] input[placeholder='Search...']"
    assert_select "[data-playground-tools='page_librarian@1'] input[name='tools[]'][value='find_page@1']"
    assert_select "[data-playground-tools='page_librarian@1'] input[name='tools[]'][value='list_pages@1']"
    assert_select "[data-playground-tools='page_librarian@1'] input[name='tools[]'][value='retitle_page@1']"
    assert_select "input[name='tools[]'][type='checkbox']", count: 0
    assert_select "input[name='choices'][value='1']"
    assert_includes response.body, "Page librarian"
    assert_includes response.body, "Support clerk"
    assert_select "a[href='/playground']", text: /Playground/
    defaults = JSON.parse(css_select("script#playground-skill-defaults").text)
    assert_equal [ "page_lookup@1" ], defaults["page_librarian@1"]
    assert_equal [ "support_voice@1" ], defaults["support_clerk@1"]
  end

  test "page librarian run shows steps and the reply" do
    assert_enqueued_jobs 1, only: PlaygroundRunJob do
      post "/playground", params: {
        agent: "page_librarian@1",
        goal: "Find the Getting Started page."
      }
    end

    assert_response :redirect
    path = redirected_playground_path
    assert_match %r{\A/playground/runs/playground:[0-9a-f-]{36}\z}, path

    get path
    assert_response :success
    assert_select "[data-controller='flat-pack--collapse']", count: 0
    refute_includes response.body, "Starting."
    assert_includes response.body, "md:grid-cols-2"
    assert_select "textarea[name='goal']", text: "Find the Getting Started page."
    assert_includes response.body, "http-equiv=\"refresh\""

    perform_enqueued_jobs
    get path
    assert_response :success
    assert_select "textarea[name='goal']", text: "Find the Getting Started page."
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Find page/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Done/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Reply/
    assert_select "#playground-reply-content[hidden]", text: /Finished\./
    assert_select "#playground-reply-content", text: /Used Find page\./, count: 0
    assert_select "h2", text: "Page librarian", count: 0
    assert_select "h2", text: "Skills", count: 0
    assert_select "h2", text: "Reply", count: 0
    refute_includes response.body, "Open the model call"
    assert_not_includes response.body, "http-equiv=\"refresh\""

    run = RecordingStudioAgents::AgentRun.find_by!(
      root_recording_id: @root.id,
      idempotency_key: path.split("/").last
    )
    assert_equal "page_librarian", run.agent_key
    assert_equal "succeeded", run.status
  end

  test "support clerk keeps the selected skills" do
    assert_enqueued_jobs 1, only: PlaygroundRunJob do
      post "/playground", params: {
        choices: "1",
        agent: "support_clerk@1",
        goal: "Help with this refund.",
        skills: [ "billing_help@1", "support_voice@1" ]
      }
    end

    assert_response :redirect
    perform_enqueued_jobs

    run = RecordingStudioAgents::AgentRun.find_by!(
      root_recording_id: @root.id,
      idempotency_key: redirected_playground_path.split("/").last
    )
    assert_equal [
      { "key" => "billing_help", "version" => 1 },
      { "key" => "support_voice", "version" => 1 }
    ], run.selected_skills_json
    assert_nil run.skill_pack_key

    get redirected_playground_path
    assert_select "[data-playground-skills] input[name='skills[]'][value='billing_help@1']"
    assert_select "[data-playground-skills] input[name='skills[]'][value='support_voice@1']"
    refute_includes response.body, "Open the model call"
  end

  test "page librarian can run with find page only" do
    assert_enqueued_jobs 1, only: PlaygroundRunJob do
      post "/playground", params: {
        choices: "1",
        agent: "page_librarian@1",
        goal: "Find the Getting Started page.",
        skills: [ "page_lookup@1" ],
        tools: [ "find_page@1" ]
      }
    end

    assert_response :redirect
    perform_enqueued_jobs
    path = redirected_playground_path
    get path

    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Find page/
    assert_select "#playground-reply-content[hidden]", text: /Finished\./
    assert_select "[id^='playground-step-'][id$='-content']", text: /Used Find page\./
    run = RecordingStudioAgents::AgentRun.find_by!(
      root_recording_id: @root.id,
      idempotency_key: path.split("/").last
    )
    definition = RecordingStudioAgents.agents.fetch(:page_librarian, version: 1)
    selection = RecordingStudioAgents::SkillSelection.explicit(skills: { page_lookup: 1 })
    program = RecordingStudioAgents::Programs::Compiler.compile(
      definition: definition,
      selection: selection,
      tools: { find_page: 1 }
    )
    assert_equal program.digest, run.program_digest
  end

  test "a skill that needs an unchecked tool redisplays and does not enqueue" do
    assert_no_enqueued_jobs do
      post "/playground", params: {
        choices: "1",
        agent: "page_librarian@1",
        goal: "Find the Getting Started page.",
        skills: [ "page_lookup@1" ],
        tools: [ "retitle_page@1" ]
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Page lookup needs Find page."
    assert_select "textarea[name='goal']"
    assert_select "[data-playground-tools='page_librarian@1'] input[name='tools[]'][value='retitle_page@1']"
    assert_select "[data-playground-tools='page_librarian@1'] input[name='tools[]'][value='find_page@1']", count: 0
  end

  test "page librarian can take a skill it did not declare" do
    assert_enqueued_jobs 1, only: PlaygroundRunJob do
      post "/playground", params: {
        choices: "1",
        agent: "page_librarian@1",
        goal: "Find the Getting Started page.",
        skills: [ "billing_help@1", "page_lookup@1" ],
        tools: [ "find_page@1", "retitle_page@1" ]
      }
    end

    assert_response :redirect
    perform_enqueued_jobs
    run = RecordingStudioAgents::AgentRun.find_by!(
      root_recording_id: @root.id,
      idempotency_key: redirected_playground_path.split("/").last
    )
    assert_includes run.selected_skills_json, { "key" => "billing_help", "version" => 1 }
    assert_equal "succeeded", run.status
  end

  test "invalid context redisplays the form and does not enqueue" do
    assert_no_enqueued_jobs do
      post "/playground", params: {
        agent: "page_librarian@1",
        goal: "Find the Getting Started page.",
        context: "{not json"
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "That is not JSON."
    assert_select "textarea[name='goal']"
  end

  test "an extra skill the agent did not allow redisplays and does not enqueue" do
    assert_no_enqueued_jobs do
      post "/playground", params: {
        agent: "page_librarian@1",
        goal: "Find the Getting Started page.",
        extra_skills: [ "billing_help@1" ]
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "That extra help is not on this agent."
    assert_select "textarea[name='goal']"
  end

  test "signed out playground is not public" do
    sign_out @user

    get "/playground"

    assert_includes [ 302, 401 ], response.status
  end

  private

  def redirected_playground_path
    location = URI.parse(response.location)
    URI.decode_www_form_component(location.path)
  end
end
