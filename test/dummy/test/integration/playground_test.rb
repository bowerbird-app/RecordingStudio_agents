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
    assert_select "select[name='profile'] option[value='low']", text: "Low"
    assert_select "select[name='profile'] option[value='medium']", text: "Medium"
    assert_select "select[name='profile'] option[value='high']", text: "High"
    assert_select "select[name='profile'] option[selected][value='medium']"
    profiles = JSON.parse(css_select("script#playground-profile-defaults").text)
    assert_equal "medium", profiles["page_librarian@1"]
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
    assert_select "meta[http-equiv=refresh]", count: 0
    assert_select "[data-controller='playground-watch'][data-playground-watch-active-value='true']"
    assert_includes response.body, "#{path}?steps=1"

    get "#{path}?steps=1"
    assert_response :success
    assert_select "textarea", count: 0
    assert_select "#playground-steps-frame[data-watching='true']"
    assert_select "[data-controller='flat-pack--collapse']", count: 0

    perform_enqueued_jobs
    get path
    assert_response :success
    assert_select "textarea[name='goal']", text: "Find the Getting Started page."
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Plan/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /List pages/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Find page/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Decision/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Answer/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Done/
    notes = css_select("[data-playground-step-list] pre").map { |node| node.text.strip }
    assert_includes notes, librarian_plan_note
    assert_includes notes, "Listed the pages."
    assert_includes notes, "Found the page."
    assert_includes notes, "Medium gemini-2.5-pro\n\nFound Getting Started."
    assert_includes notes, <<~TEXT.chomp
      Low jev-latest

      Picked tool: List pages.
      Finished 0.10. Stuck 0.05.
    TEXT
    assert_includes notes, <<~TEXT.chomp
      Low jev-latest

      Picked tool: Find page.
      Finished 0.10. Stuck 0.05.
    TEXT
    refute_includes notes.reject { |text| text.include?("\nPlan\n") }.join("\n"), "Find the named page"
    refute_includes notes.join("\n"), "arguments"
    refute_includes response.body, "Finished."
    refute_includes response.body, ">Given<"
    refute_includes response.body, ">Returned<"
    assert_select "h2", text: "Page librarian", count: 0
    assert_select "h2", text: "Skills", count: 0
    assert_select "h2", text: "Reply", count: 0
    refute_includes response.body, "Open the model call"
    assert_select "meta[http-equiv=refresh]", count: 0
    assert_select "[data-controller='playground-watch']", count: 0

    get "#{path}?steps=1"
    assert_response :success
    assert_select "textarea", count: 0
    assert_select "#playground-steps-frame[data-watching='false']"
    assert_select "[data-playground-step-list]"
    assert_select "#playground-step-0-content"
    assert_select "#playground-step-1-content"

    run = RecordingStudioAgents::AgentRun.find_by!(
      root_recording_id: @root.id,
      idempotency_key: path.split("/").last
    )
    assert_equal "page_librarian", run.agent_key
    assert_equal "succeeded", run.status
    assert_equal "medium", RecordingStudioAI::Run.find(run.recording_studio_ai_run_id).profile_key
  end

  test "a playground run can pick a profile" do
    assert_enqueued_jobs 1, only: PlaygroundRunJob do
      post "/playground", params: {
        choices: "1",
        agent: "page_librarian@1",
        goal: "Find the Getting Started page.",
        skills: [ "page_lookup@1" ],
        tools: [ "find_page@1", "list_pages@1" ],
        profile: "high"
      }
    end

    assert_response :redirect
    perform_enqueued_jobs
    path = redirected_playground_path
    get path

    assert_select "select[name='profile'] option[selected][value='high']"
    run = RecordingStudioAgents::AgentRun.find_by!(
      root_recording_id: @root.id,
      idempotency_key: path.split("/").last
    )
    assert_equal "high", RecordingStudioAI::Run.find(run.recording_studio_ai_run_id).profile_key
  end

  test "a playground run rejects an unknown profile" do
    assert_no_enqueued_jobs only: PlaygroundRunJob do
      post "/playground", params: {
        choices: "1",
        agent: "page_librarian@1",
        goal: "Find the Getting Started page.",
        profile: "turbo"
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Pick Low, Medium, or High."
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

    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Plan/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Find page/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /Answer/
    assert_select "[data-flat-pack--collapse-target='trigger']", text: /List pages/, count: 0
    notes = css_select("[data-playground-step-list] pre").map { |node| node.text.strip }
    assert_includes notes, librarian_plan_note
    assert_includes notes, "Found the page."
    assert_includes notes, "Medium gemini-2.5-pro\n\nFound Getting Started."
    refute_includes notes, "Listed the pages."
    refute_includes notes.reject { |text| text.include?("\nPlan\n") }.join("\n"), "Find the named page"
    refute_includes notes.join("\n"), "arguments"
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

  def librarian_plan_note
    <<~TEXT.chomp
      Medium gemini-2.5-pro

      Find the named page

      Plan
      List the pages
      Find the named page
      Answer

      Done when
      The named page was found
    TEXT
  end
end
