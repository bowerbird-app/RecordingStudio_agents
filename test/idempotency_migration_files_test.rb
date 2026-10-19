# frozen_string_literal: true

require "test_helper"

class IdempotencyMigrationFilesTest < Minitest::Test
  NAMES = %w[
    20261019040000_scope_agents_idempotency_keys_to_root.rb
    20261019040100_require_agents_root_on_idempotency_keys.rb
    20261019040200_add_instructions_to_recording_studio_agents_sessions.rb
  ].freeze

  def test_dummy_migration_copies_match_the_gem_files
    root = File.expand_path("..", __dir__)
    NAMES.each do |name|
      gem_copy = File.binread(File.join(root, "db/migrate", name))
      dummy_copy = File.binread(File.join(root, "test/dummy/db/migrate", name))

      assert_equal gem_copy, dummy_copy, name
    end
  end
end
