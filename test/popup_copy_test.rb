# frozen_string_literal: true

require "test_helper"
require "yaml"

class PopupCopyTest < Minitest::Test
  KEYS = %w[document_title sign_in_title sign_in_description sign_in_action].freeze

  def test_english_and_french_popup_copy_match
    english = popup_copy("en")
    french = popup_copy("fr")

    assert_equal KEYS, english.keys
    assert_equal KEYS, french.keys
    KEYS.each do |key|
      refute_empty english.fetch(key)
      refute_empty french.fetch(key)
      refute_equal english.fetch(key), french.fetch(key)
    end
  end

  private

  def popup_copy(locale)
    path = File.expand_path("../config/locales/#{locale}.yml", __dir__)
    YAML.load_file(path).dig(locale, "recording_studio_agents", "popups", "show")
  end
end
