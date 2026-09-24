# frozen_string_literal: true

# Retained model replies are encrypted. The dummy has no encryption
# credentials, so set fixture keys when the host has not configured any.
encryption = ActiveRecord::Encryption.config
unless encryption.has_primary_key?
  encryption.primary_key = "dummy-active-record-primary-key"
  encryption.deterministic_key = "dummy-active-record-deterministic-key"
  encryption.key_derivation_salt = "dummy-active-record-derivation-salt"
end
