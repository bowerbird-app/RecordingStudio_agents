# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

class PageContextScriptTest < Minitest::Test
  SCRIPT = File.expand_path("../app/assets/javascripts/recording_studio_agents/page_context.js", __dir__)

  def test_a_foreign_origin_or_source_is_ignored
    parent = { "name" => "parent" }
    result = run_js(<<~JS)
      const parent = { name: "parent" }
      const other = { name: "other" }
      const origin = "https://app.test"
      const message = {
        type: api.type,
        url: "https://app.test/home",
        title: "Home",
        selection: "hello",
        metadata: { section: "home" }
      }
      const delivered = []
      api.deliver({ postMessage: (data, target) => delivered.push(target) }, "*", message)
      api.deliver({ postMessage: (data, target) => delivered.push(target) }, origin, message)
      return {
        foreign: api.acceptMessage({ origin: "https://evil.test", source: parent, data: message }, origin, parent),
        stranger: api.acceptMessage({ origin: origin, source: other, data: message }, origin, parent),
        missing: api.acceptMessage({ origin: origin, source: null, data: message }, origin, parent),
        instructions: api.acceptMessage({
          origin: origin, source: parent, data: Object.assign({ instructions: "Be terse." }, message)
        }, origin, parent),
        accepted: api.acceptMessage({ origin: origin, source: parent, data: message }, origin, parent),
        delivered: delivered
      }
    JS

    assert_nil result["foreign"]
    assert_nil result["stranger"]
    assert_nil result["missing"]
    assert_nil result["instructions"]
    assert_equal "https://app.test/home", result.dig("accepted", "url")
    assert_equal "Home", result.dig("accepted", "title")
    assert_equal ["https://app.test"], result["delivered"]
    assert_equal parent["name"], "parent"
  end

  def test_host_page_reading_caps_selection_and_prefers_the_data_attribute
    result = run_js(<<~JS)
      const doc = {
        title: "Press kits",
        querySelector(selector) {
          if (selector.indexOf("page-metadata") !== -1) {
            return { getAttribute: () => JSON.stringify({ section: "kits", instructions: "no" }) }
          }
          if (selector.indexOf("meta") === 0) {
            return { getAttribute: () => "00000000-0000-4000-8000-000000000002" }
          }
          return { getAttribute: () => "00000000-0000-4000-8000-000000000001" }
        }
      }
      const page = api.readHostPage(doc, "https://app.test/" + "a".repeat(4000), "s".repeat(3000))
      const metaOnly = {
        title: "Home",
        querySelector(selector) {
          if (selector.indexOf("meta") === 0) {
            return { getAttribute: () => "00000000-0000-4000-8000-000000000002" }
          }
          return null
        }
      }
      return { page: page, fromMeta: api.readHostPage(metaOnly, "https://app.test/home", "") }
    JS

    assert_equal PageContextScriptTest::URL_LIMIT, result.dig("page", "url").length
    assert_equal 2000, result.dig("page", "selection").length
    assert_equal "00000000-0000-4000-8000-000000000001", result.dig("page", "page_recording_id")
    assert_nil result.dig("page", "metadata")
    assert_equal "00000000-0000-4000-8000-000000000002", result.dig("fromMeta", "page_recording_id")
  end

  URL_LIMIT = RecordingStudioAgents::ChatKit::PageContext::URL_LIMIT

  private

  def run_js(body)
    script = <<~JS
      const fs = require("fs")
      const vm = require("vm")
      const sandbox = { console }
      sandbox.globalThis = sandbox
      vm.createContext(sandbox)
      vm.runInContext(fs.readFileSync(#{JSON.generate(SCRIPT)}), sandbox)
      const api = sandbox.RecordingStudioAgentsPageContext
      const result = (function () {
        #{body}
      })()
      process.stdout.write(JSON.stringify(result))
    JS
    stdout, stderr, status = Open3.capture3("node", "-e", script)
    flunk(stderr) unless status.success?

    JSON.parse(stdout)
  end
end
