ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# Development and test share one key. The value stays in the environment.
# Do not write a key file and do not print the key.
rails_env = ENV["RAILS_ENV"].to_s
rails_env = "development" if rails_env.empty?
shared_key = ENV["EMBEDDABLE_DUMMY_DEVELOPMENT_KEY"].to_s
if %w[development test].include?(rails_env) && ENV["RAILS_MASTER_KEY"].to_s.empty? && !shared_key.empty?
  ENV["RAILS_MASTER_KEY"] = shared_key
end

require "bundler/setup" # Set up gems listed in the Gemfile.
# require "bootsnap/setup" # Speed up boot time by caching expensive operations.
