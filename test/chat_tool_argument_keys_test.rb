# frozen_string_literal: true

require "test_helper"

class ChatToolArgumentKeysTest < Minitest::Test
  def test_keys_are_capped_at_fifty_identifier_names
    keys = RecordingStudioAgents::ChatToolArgumentKeys
    long = "k" * 80
    arguments = { "bad key" => "secret", "9nope" => "secret", long => "secret" }
    55.times { |index| arguments["field_#{index}"] = "secret-#{index}" }

    stored = keys.list(arguments)

    assert_equal 50, stored.size
    assert_equal "k" * 64, stored.first
    assert_equal (0..48).map { |index| "field_#{index}" }, stored.drop(1)
    refute_includes stored, "bad key"
    refute_includes stored, "9nope"
    stored.each { |name| refute_includes name, "secret" }
  end

  def test_a_non_hash_stores_no_keys
    assert_empty RecordingStudioAgents::ChatToolArgumentKeys.list("name")
    assert_empty RecordingStudioAgents::ChatToolArgumentKeys.list(nil)
  end
end
