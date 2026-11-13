# frozen_string_literal: true

require "test_helper"

class PageContextTest < Minitest::Test
  Context = RecordingStudioAgents::ChatKit::PageContext

  def test_blank_context_has_no_preface
    context = Context.parse(nil)

    assert_nil context.preface
    assert_equal "hello", Context.model_input("hello", context.preface)
  end

  def test_fields_are_capped_and_unsafe_metadata_is_dropped
    raw = {
      "url" => " https://studio.test/#{'a' * 4000} ",
      "title" => "t" * 500,
      "selection" => "s" * 3000,
      "page_recording_id" => "not-a-page",
      "metadata" => {
        "section" => "n" * 500,
        "bad key" => "x",
        "nested" => { "no" => true },
        "published" => true,
        "count" => 2
      }
    }

    context = Context.parse(raw.to_json)
    preface = context.preface

    assert_includes preface, "URL: https://studio.test/#{'a' * (Context::URL_LIMIT - 'https://studio.test/'.length)}"
    refute_includes preface, "a" * 4000
    assert_includes preface, "Title: #{'t' * Context::TITLE_LIMIT}"
    refute_includes preface, "t" * 301
    assert_includes preface, "Selection: #{'s' * Context::SELECTION_LIMIT}"
    refute_includes preface, "Page:"
    assert_includes preface, '"section":'
    assert_includes preface, "n" * Context::METADATA_VALUE_LIMIT
    refute_includes preface, "n" * (Context::METADATA_VALUE_LIMIT + 1)
    refute_includes preface, "bad key"
    refute_includes preface, "nested"
    assert_includes preface, '"published":true'
    assert_includes preface, '"count":2'
  end

  def test_instructions_are_rejected
    ["Be terse.", "  ", { "tone" => "terse" }, "a" * 4001].each do |instructions|
      error = assert_raises(RecordingStudioAgents::ChatKit::ProtocolError) do
        Context.parse({ "url" => "https://studio.test", "instructions" => instructions }.to_json)
      end
      assert_equal "ChatKit does not accept instructions", error.message
    end

    nested = assert_raises(RecordingStudioAgents::ChatKit::ProtocolError) do
      Context.parse({ "metadata" => { "instructions" => "Be terse." } }.to_json)
    end
    assert_equal "ChatKit does not accept instructions", nested.message
  end

  def test_a_bad_or_huge_header_is_rejected
    invalid = assert_raises(RecordingStudioAgents::ChatKit::ProtocolError) { Context.parse("{") }
    huge = assert_raises(RecordingStudioAgents::ChatKit::ProtocolError) { Context.parse("x" * (Context::HEADER_LIMIT + 1)) }

    assert_equal "page context must be an object", invalid.message
    assert_equal "page context is too large", huge.message
  end

  def test_a_resolved_page_is_named_only_when_it_matches
    context = Context.parse({ "url" => "https://studio.test/kits", "page_recording_id" => PAGE_ID }.to_json)
    page = Struct.new(:id).new(PAGE_ID)
    other = Struct.new(:id).new("00000000-0000-4000-8000-000000000002")

    assert_includes context.preface(page), "Page: #{PAGE_ID}"
    refute_includes context.preface(other), "Page:"
    assert_equal "Page context:\nURL: https://studio.test/kits\n\nhello", Context.model_input("hello", context.preface)
  end

  def test_the_script_uses_the_same_limits_and_header
    source = File.read(File.expand_path("../app/assets/javascripts/recording_studio_agents/page_context.js", __dir__))
    launcher = File.read(File.expand_path("../app/assets/javascripts/recording_studio_agents/launcher.js", __dir__))

    assert_includes source, "url: #{Context::URL_LIMIT}"
    assert_includes source, "title: #{Context::TITLE_LIMIT}"
    assert_includes source, "selection: #{Context::SELECTION_LIMIT}"
    assert_includes source, "metadata: #{Context::METADATA_LIMIT}"
    assert_includes source, Context::HEADER
    assert_includes launcher, "window.location.origin"
    assert_includes launcher, "api.deliver(iframe.contentWindow, window.location.origin, api.readHostPage())"
    refute_includes launcher, "document.cookie"
    refute_includes launcher, '"*"'
  end

  PAGE_ID = "00000000-0000-4000-8000-000000000001"
end
