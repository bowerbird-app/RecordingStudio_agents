# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_21_143000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "press_kits", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug"
    t.jsonb "sections", default: [], null: false
  end

  create_table "recording_studio_access_constraints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.string "allowed_audiences", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_recording_studio_access_constraints_on_action"
  end

  create_table "recording_studio_access_invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "recording_id", null: false
    t.string "email", null: false
    t.string "role", null: false
    t.string "token_digest", limit: 64, null: false
    t.string "manager_actor_type", null: false
    t.uuid "manager_actor_id", null: false
    t.string "accepted_by_actor_type"
    t.uuid "accepted_by_actor_id"
    t.datetime "expires_at", null: false
    t.datetime "last_sent_at", null: false
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recording_id", "email"], name: "idx_rs_access_invitations_one_active", unique: true, where: "((accepted_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["recording_id"], name: "index_recording_studio_access_invitations_on_recording_id"
    t.index ["token_digest"], name: "idx_rs_access_invitations_token_digest", unique: true
    t.check_constraint "accepted_at IS NULL OR revoked_at IS NULL", name: "access_invitations_not_accepted_and_revoked"
  end

  create_table "recording_studio_access_request_intents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "recording_id", null: false
    t.uuid "user_id", null: false
    t.uuid "otp_challenge_id", null: false
    t.string "email", null: false
    t.string "role"
    t.string "action"
    t.datetime "expires_at", null: false
    t.datetime "fulfilled_at"
    t.datetime "created_at", null: false
    t.string "submitted_name"
    t.index ["recording_id"], name: "index_recording_studio_access_request_intents_on_recording_id"
    t.check_constraint "action IS NULL OR char_length(action::text) <= 120", name: "recording_studio_access_request_intents_action_length"
    t.check_constraint "char_length(email::text) <= 255", name: "recording_studio_access_request_intents_email_length"
    t.check_constraint "submitted_name IS NULL OR char_length(submitted_name::text) <= 120", name: "recording_studio_access_request_intents_name_length"
  end

  create_table "recording_studio_access_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_type", null: false
    t.uuid "actor_id", null: false
    t.string "role"
    t.string "action"
    t.text "message"
    t.string "status", default: "pending", null: false
    t.uuid "access_recording_id"
    t.text "review_note"
    t.datetime "created_at", null: false
    t.jsonb "gate_metadata", default: {}, null: false
    t.uuid "target_recording_id", null: false
    t.string "pending_key"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_access_requests_on_actor"
    t.index ["pending_key"], name: "index_recording_studio_access_requests_one_pending", unique: true, where: "(pending_key IS NOT NULL)"
    t.check_constraint "action IS NULL OR char_length(action::text) <= 120", name: "recording_studio_access_requests_action_length"
    t.check_constraint "message IS NULL OR char_length(message) <= 2000", name: "recording_studio_access_requests_message_length"
    t.check_constraint "review_note IS NULL OR char_length(review_note) <= 2000", name: "recording_studio_access_requests_note_length"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'denied'::character varying::text])", name: "recording_studio_access_requests_status"
  end

  create_table "recording_studio_access_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.string "audience", null: false
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_recording_studio_access_rules_on_action"
  end

  create_table "recording_studio_accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.string "actor_type", null: false
    t.datetime "created_at", null: false
    t.uuid "depends_on_recording_id"
    t.string "role", default: "view", null: false
    t.index ["actor_type", "actor_id", "role"], name: "index_recording_studio_accesses_on_actor_and_role"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_accesses_on_actor"
    t.index ["depends_on_recording_id"], name: "index_recording_studio_accesses_on_depends_on_recording_id"
  end

  create_table "recording_studio_agents_bindings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "recording_id", null: false
    t.string "provider", null: false
    t.string "provider_session_id"
    t.string "preview"
    t.string "create_idempotency_key", null: false
    t.datetime "last_activity_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "root_recording_id", null: false
    t.index ["expires_at"], name: "index_recording_studio_agents_bindings_on_expires_at"
    t.index ["provider_session_id"], name: "index_rs_agents_bindings_on_provider_session", unique: true, where: "(provider_session_id IS NOT NULL)"
    t.index ["recording_id"], name: "index_recording_studio_agents_bindings_on_recording_id", unique: true
    t.index ["root_recording_id", "create_idempotency_key"], name: "index_rs_agents_bindings_on_root_and_create_key", unique: true
  end

  create_table "recording_studio_agents_items", id: :string, force: :cascade do |t|
    t.uuid "recording_id", null: false
    t.string "provider_item_id"
    t.string "role", null: false
    t.text "text", null: false
    t.string "status", default: "done", null: false
    t.string "idempotency_key"
    t.datetime "created_at", null: false
    t.uuid "root_recording_id", null: false
    t.index ["recording_id"], name: "index_recording_studio_agents_items_on_recording_id"
    t.index ["root_recording_id", "idempotency_key"], name: "index_rs_agents_items_on_root_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
  end

  create_table "recording_studio_agents_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title"
    t.string "status", null: false
    t.string "model", null: false
    t.string "profile"
    t.string "purpose"
    t.datetime "created_at", null: false
    t.text "instructions"
  end

  create_table "recording_studio_api_admin_apis", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_recording_studio_api_admin_apis_on_key", unique: true
  end

  create_table "recording_studio_api_api_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_credential_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_credential_id"], name: "idx_on_api_credential_id_89874cbf51"
    t.index ["expires_at"], name: "index_recording_studio_api_api_access_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_recording_studio_api_api_access_tokens_on_token_digest", unique: true
  end

  create_table "recording_studio_api_api_clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["access_recording_id"], name: "index_recording_studio_api_api_clients_on_access_recording_id", unique: true
    t.index ["api_key"], name: "index_recording_studio_api_api_clients_on_api_key"
  end

  create_table "recording_studio_api_api_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_client_id", null: false
    t.uuid "access_recording_id", null: false
    t.string "token_public_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["access_recording_id"], name: "idx_on_access_recording_id_103368144f"
    t.index ["api_client_id"], name: "index_recording_studio_api_api_credentials_on_api_client_id"
    t.index ["api_client_id"], name: "index_recording_studio_api_credentials_on_active_client", unique: true, where: "(revoked_at IS NULL)"
    t.index ["token_digest"], name: "index_recording_studio_api_api_credentials_on_token_digest", unique: true
    t.index ["token_public_id"], name: "index_recording_studio_api_api_credentials_on_token_public_id", unique: true
  end

  create_table "recording_studio_api_api_daily_latency_histogram_buckets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "metric_date", null: false
    t.string "route_name", null: false
    t.string "request_method", null: false
    t.integer "status_class", null: false
    t.integer "upper_bound_ms", null: false
    t.bigint "request_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class", "upper_bound_ms"], name: "index_rs_api_daily_latency_histogram_on_dimensions", unique: true
    t.index ["metric_date"], name: "idx_on_metric_date_8723beba88"
  end

  create_table "recording_studio_api_api_daily_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "metric_date", null: false
    t.string "route_name", null: false
    t.string "controller_name"
    t.string "action_name"
    t.string "request_method", null: false
    t.integer "status_class", null: false
    t.bigint "request_count", default: 0, null: false
    t.bigint "rate_limited_count", default: 0, null: false
    t.bigint "client_error_count", default: 0, null: false
    t.bigint "server_error_count", default: 0, null: false
    t.bigint "duration_count", default: 0, null: false
    t.bigint "duration_sum_ms", default: 0, null: false
    t.integer "duration_max_ms", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class"], name: "index_rs_api_daily_metrics_on_dimensions", unique: true
    t.index ["metric_date"], name: "index_recording_studio_api_api_daily_metrics_on_metric_date"
  end

  create_table "recording_studio_api_api_request_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.string "request_id"
    t.string "request_method", null: false
    t.string "request_path", null: false
    t.string "route_name"
    t.string "controller_name"
    t.string "action_name"
    t.integer "status_code", null: false
    t.integer "duration_ms", null: false
    t.boolean "rate_limited", default: false, null: false
    t.uuid "api_client_id"
    t.uuid "api_credential_id"
    t.uuid "access_recording_id"
    t.uuid "root_recording_id"
    t.string "remote_ip"
    t.string "user_agent"
    t.string "error_class"
    t.string "error_message"
    t.jsonb "request_params", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["api_client_id", "occurred_at"], name: "index_rs_api_request_logs_on_client_and_time"
    t.index ["api_credential_id", "occurred_at"], name: "index_rs_api_request_logs_on_credential_and_time"
    t.index ["api_key", "occurred_at"], name: "index_rs_api_request_logs_on_api_and_time"
    t.index ["occurred_at"], name: "index_recording_studio_api_api_request_logs_on_occurred_at"
    t.index ["request_id"], name: "index_recording_studio_api_api_request_logs_on_request_id"
    t.index ["request_path"], name: "index_recording_studio_api_api_request_logs_on_request_path"
    t.index ["status_code"], name: "index_recording_studio_api_api_request_logs_on_status_code"
  end

  create_table "recording_studio_api_api_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.boolean "api_access_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "runtime_overrides", default: {}, null: false
    t.index ["key"], name: "index_recording_studio_api_api_settings_on_key", unique: true
  end

  create_table "recording_studio_attachable_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "attachment_kind", null: false
    t.string "original_filename", null: false
    t.string "content_type", null: false
    t.bigint "byte_size", null: false
    t.uuid "root_recording_id"
    t.text "caption"
    t.text "credit"
    t.text "alt_text"
    t.index ["attachment_kind", "content_type"], name: "idx_rs_attachable_kind_type"
    t.index ["attachment_kind"], name: "idx_on_attachment_kind_d683071625"
    t.index ["root_recording_id"], name: "index_rs_attachable_attachments_on_root_recording_id"
  end

  create_table "recording_studio_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.uuid "impersonator_id"
    t.string "impersonator_type"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "previous_recordable_id"
    t.string "previous_recordable_type"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "recording_id", null: false
    t.index ["action", "occurred_at"], name: "index_rs_events_on_action_and_occurred_at"
    t.index ["actor_type", "actor_id", "occurred_at"], name: "index_rs_events_on_actor_and_occurred_at"
    t.index ["recording_id", "idempotency_key"], name: "index_recording_studio_events_on_recording_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recording_id", "occurred_at", "created_at"], name: "index_rs_events_on_recording_and_timeline", order: { occurred_at: :desc, created_at: :desc }
    t.index ["recording_id"], name: "index_recording_studio_events_on_recording_id"
  end

  create_table "recording_studio_mcp_event_subscriptions", id: :string, force: :cascade do |t|
    t.string "owner_principal_id", null: false
    t.uuid "access_recording_id"
    t.string "event_name", null: false
    t.jsonb "arguments", default: {}, null: false
    t.string "callback_url", null: false
    t.text "callback_secret", null: false
    t.string "status", default: "active", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_delivered_at"
    t.string "last_error"
    t.integer "failure_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_name", "status"], name: "index_rs_mcp_event_subs_on_event_and_status"
    t.index ["owner_principal_id"], name: "index_rs_mcp_event_subs_on_owner"
  end

  create_table "recording_studio_mcp_usage_daily_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "metric_date", null: false
    t.string "method_name", null: false
    t.string "subject_name", default: "", null: false
    t.integer "call_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.integer "rate_limited_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["metric_date", "method_name", "subject_name"], name: "index_rs_mcp_usage_daily_on_day_method_subject", unique: true
  end

  create_table "recording_studio_mcp_usage_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.string "method_name", null: false
    t.string "subject_name", default: "", null: false
    t.integer "status_code", null: false
    t.integer "duration_ms", null: false
    t.boolean "rate_limited", default: false, null: false
    t.boolean "failed", default: false, null: false
    t.uuid "api_client_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_client_id", "occurred_at"], name: "index_rs_mcp_usage_logs_on_client_and_time"
    t.index ["occurred_at"], name: "index_recording_studio_mcp_usage_logs_on_occurred_at"
  end

  create_table "recording_studio_oauth_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "oauth_authorization_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_used_at"
    t.index ["expires_at"], name: "index_recording_studio_oauth_access_tokens_on_expires_at"
    t.index ["oauth_authorization_id"], name: "idx_on_oauth_authorization_id_7313b03aba"
    t.index ["token_digest"], name: "index_recording_studio_oauth_access_tokens_on_token_digest", unique: true
  end

  create_table "recording_studio_oauth_authorization_codes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "oauth_authorization_id", null: false
    t.string "code_digest", null: false
    t.string "redirect_uri", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_digest"], name: "idx_on_code_digest_bcebd970b4", unique: true
    t.index ["expires_at"], name: "index_recording_studio_oauth_authorization_codes_on_expires_at"
    t.index ["oauth_authorization_id"], name: "idx_on_oauth_authorization_id_4cb485335a"
  end

  create_table "recording_studio_oauth_authorizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "oauth_client_id", null: false
    t.string "manager_actor_type", null: false
    t.uuid "manager_actor_id", null: false
    t.uuid "manager_access_recording_id", null: false
    t.uuid "access_recording_id"
    t.string "role", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["access_recording_id"], name: "idx_on_access_recording_id_94e16371a2"
    t.index ["manager_access_recording_id"], name: "idx_on_manager_access_recording_id_ee8e9d6f9c"
    t.index ["manager_actor_type", "manager_actor_id"], name: "index_rs_oauth_authorizations_on_manager_actor"
    t.index ["oauth_client_id", "manager_actor_type", "manager_actor_id", "manager_access_recording_id"], name: "index_rs_oauth_authorizations_unique_active", unique: true, where: "(revoked_at IS NULL)"
    t.index ["oauth_client_id"], name: "index_recording_studio_oauth_authorizations_on_oauth_client_id"
    t.index ["revoked_at"], name: "index_recording_studio_oauth_authorizations_on_revoked_at"
  end

  create_table "recording_studio_oauth_clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "client_id", null: false
    t.string "client_secret_digest"
    t.jsonb "redirect_uris", default: [], null: false
    t.boolean "confidential", default: true, null: false
    t.string "api_key", default: "public", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "use_central_relay", default: false, null: false
    t.jsonb "allowed_return_patterns", default: [], null: false
    t.jsonb "exact_return_urls", default: [], null: false
    t.boolean "allow_registration", default: false, null: false
    t.string "session_token_provider"
    t.string "session_token_audience"
    t.text "session_token_secret_ciphertext"
    t.boolean "self_registered", default: false, null: false
    t.string "token_endpoint_auth_method", null: false
    t.index ["api_key"], name: "index_recording_studio_oauth_clients_on_api_key"
    t.index ["client_id"], name: "index_recording_studio_oauth_clients_on_client_id", unique: true
  end

  create_table "recording_studio_oauth_external_installs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "oauth_client_id", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.uuid "root_recording_id"
    t.string "connected_by_type"
    t.uuid "connected_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connected_by_type", "connected_by_id"], name: "index_rs_oauth_external_installs_on_connected_by"
    t.index ["oauth_client_id", "provider", "external_id"], name: "index_rs_oauth_external_installs_on_client_provider_external", unique: true
    t.index ["provider", "external_id"], name: "index_rs_oauth_external_installs_on_provider_external"
    t.index ["root_recording_id"], name: "idx_on_root_recording_id_efcab19ee0"
  end

  create_table "recording_studio_oauth_refresh_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "oauth_authorization_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.uuid "replaced_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_recording_studio_oauth_refresh_tokens_on_expires_at"
    t.index ["oauth_authorization_id"], name: "idx_on_oauth_authorization_id_a1e93340c5"
    t.index ["replaced_by_id"], name: "index_recording_studio_oauth_refresh_tokens_on_replaced_by_id"
    t.index ["token_digest"], name: "index_recording_studio_oauth_refresh_tokens_on_token_digest", unique: true
  end

  create_table "recording_studio_recordings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "parent_recording_id"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "root_recording_id"
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.boolean "trash_root", default: false, null: false
    t.index ["parent_recording_id"], name: "idx_rs_attachable_parent_active", where: "(((recordable_type)::text = 'RecordingStudioAttachable::Attachment'::text) AND (trashed_at IS NULL))"
    t.index ["parent_recording_id"], name: "index_recording_studio_recordings_on_parent_recording_id"
    t.index ["recordable_type", "recordable_id", "parent_recording_id", "trashed_at"], name: "index_recording_studio_recordings_on_recordable_parent_trashed"
    t.index ["recordable_type", "recordable_id"], name: "index_recording_studio_recordings_on_recordable"
    t.index ["recordable_type", "recordable_id"], name: "index_rs_unique_root_recording_per_recordable", unique: true, where: "(parent_recording_id IS NULL)"
    t.index ["root_recording_id", "parent_recording_id"], name: "index_rs_recordings_on_root_and_parent"
    t.index ["root_recording_id", "recordable_type", "recordable_id"], name: "index_rs_recordings_on_root_and_recordable"
    t.index ["root_recording_id"], name: "idx_rs_attachable_root_active", where: "(((recordable_type)::text = 'RecordingStudioAttachable::Attachment'::text) AND (trashed_at IS NULL))"
    t.index ["root_recording_id"], name: "index_rs_recordings_on_root_recording"
    t.index ["trashed_at", "trash_root"], name: "idx_rs_recordings_trashed_at_trash_root"
    t.index ["trashed_at"], name: "index_recording_studio_recordings_on_trashed_at"
  end

  create_table "recording_studio_root_switchable_selections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "device_browser"
    t.string "device_key", null: false
    t.string "device_label"
    t.string "device_platform"
    t.string "device_type"
    t.datetime "last_used_at", null: false
    t.uuid "root_recording_id", null: false
    t.string "scope_key", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["actor_type", "actor_id", "device_key", "scope_key"], name: "idx_rs_root_switchable_actor_device_scope", unique: true, where: "(actor_id IS NOT NULL)"
    t.index ["device_key", "scope_key"], name: "idx_rs_root_switchable_anonymous_device_scope", unique: true, where: "(actor_id IS NULL)"
    t.index ["root_recording_id"], name: "idx_rs_root_switchable_root_recording"
  end

  create_table "recording_studio_site_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
  end

  create_table "recording_studio_trashable_retention_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "recording_id", null: false
    t.integer "purge_after_days"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recording_id"], name: "idx_rs_trashable_retention_on_recording", unique: true
  end

  create_table "recording_studio_user_identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "uid"], name: "index_recording_studio_user_identities_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_recording_studio_user_identities_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_recording_studio_user_identities_on_user_id"
  end

  create_table "recording_studio_user_otp_challenges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "purpose", null: false
    t.string "code_digest", null: false
    t.text "delivery_code_ciphertext"
    t.datetime "expires_at", null: false
    t.integer "attempts_count", default: 0, null: false
    t.datetime "verified_at"
    t.datetime "consumed_at"
    t.datetime "revoked_at"
    t.datetime "delivery_requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_recording_studio_user_otp_challenges_on_expires_at"
    t.index ["user_id", "purpose"], name: "idx_on_user_id_purpose_2b7c2a59c4"
    t.index ["user_id", "purpose"], name: "index_rs_user_otp_challenges_open_purpose", unique: true, where: "((consumed_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["user_id"], name: "index_recording_studio_user_otp_challenges_on_user_id"
  end

  create_table "recording_studio_user_people", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
  end

  create_table "recording_studio_user_profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "first_name", null: false
    t.string "last_name"
    t.string "time_zone", default: "UTC"
    t.jsonb "additional_profile_attributes", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["user_id"], name: "index_recording_studio_user_profiles_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.string "registered_with", default: "password", null: false
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.check_constraint "registered_with::text = ANY (ARRAY['password'::character varying::text, 'otp'::character varying::text])", name: "users_registered_with_check"
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "recording_studio_access_invitations", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_agents_bindings", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_agents_bindings", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_agents_items", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_agents_items", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_api_api_access_tokens", "recording_studio_api_api_credentials", column: "api_credential_id"
  add_foreign_key "recording_studio_api_api_credentials", "recording_studio_api_api_clients", column: "api_client_id"
  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_oauth_access_tokens", "recording_studio_oauth_authorizations", column: "oauth_authorization_id"
  add_foreign_key "recording_studio_oauth_authorization_codes", "recording_studio_oauth_authorizations", column: "oauth_authorization_id"
  add_foreign_key "recording_studio_oauth_authorizations", "recording_studio_oauth_clients", column: "oauth_client_id"
  add_foreign_key "recording_studio_oauth_external_installs", "recording_studio_oauth_clients", column: "oauth_client_id"
  add_foreign_key "recording_studio_oauth_external_installs", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_oauth_refresh_tokens", "recording_studio_oauth_authorizations", column: "oauth_authorization_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "parent_recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_trashable_retention_settings", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_user_identities", "users"
  add_foreign_key "recording_studio_user_otp_challenges", "users"
  add_foreign_key "recording_studio_user_profiles", "users"
end
