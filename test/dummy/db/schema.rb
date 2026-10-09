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

ActiveRecord::Schema[8.1].define(version: 2026_10_09_083022) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "admin_audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "event_id", null: false
    t.string "resource_key", null: false
    t.string "action_key", null: false
    t.string "outcome", null: false
    t.string "actor_type"
    t.string "actor_id"
    t.string "record_type"
    t.string "record_id"
    t.uuid "access_recording_id"
    t.string "surface_key"
    t.string "http_method"
    t.boolean "destructive"
    t.string "required_role"
    t.string "blast_radius"
    t.string "request_id"
    t.string "ip_address"
    t.string "user_agent"
    t.jsonb "metadata", default: {}, null: false
    t.string "error_class"
    t.text "error_message"
    t.string "recording_studio_event_id"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_admin_audit_logs_on_event_id", unique: true
    t.index ["occurred_at"], name: "index_admin_audit_logs_on_occurred_at"
    t.index ["outcome"], name: "index_admin_audit_logs_on_outcome"
    t.index ["resource_key", "action_key"], name: "index_admin_audit_logs_on_resource_key_and_action_key"
  end

  create_table "admin_roots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", default: "Admin", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "recording_studio_accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_type", null: false
    t.uuid "actor_id", null: false
    t.string "role", default: "view", null: false
    t.datetime "created_at", null: false
    t.uuid "depends_on_recording_id"
    t.index ["actor_type", "actor_id", "role"], name: "index_recording_studio_accesses_on_actor_and_role"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_accesses_on_actor"
    t.index ["depends_on_recording_id"], name: "index_recording_studio_accesses_on_depends_on_recording_id"
  end

  create_table "recording_studio_agents_agent_runs", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.uuid "root_recording_id", null: false
    t.uuid "context_recording_id"
    t.string "agent_key", null: false
    t.integer "agent_version", null: false
    t.string "program_digest", null: false
    t.string "idempotency_key", null: false
    t.string "status", default: "pending", null: false
    t.bigint "recording_studio_ai_run_id"
    t.string "initiator_type", null: false
    t.string "initiator_id", null: false
    t.string "initiator_kind", null: false
    t.string "executor_type"
    t.string "executor_id"
    t.string "execution_source", null: false
    t.string "lease_token"
    t.datetime "lease_expires_at"
    t.string "handoff_agent_key"
    t.integer "handoff_agent_version"
    t.string "failure_category"
    t.string "failure_code"
    t.text "failure_message"
    t.boolean "failure_retryable"
    t.string "output_digest"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "selected_skills_json", default: [], null: false
    t.string "skill_pack_key"
    t.integer "skill_pack_version"
    t.json "handoff_allowlist_json", default: [], null: false
    t.json "working_state_json", default: {}, null: false
    t.index ["recording_studio_ai_run_id"], name: "index_rsa_runs_on_ai_run_id", unique: true, where: "(recording_studio_ai_run_id IS NOT NULL)"
    t.index ["root_recording_id", "agent_key", "agent_version", "idempotency_key"], name: "index_rsa_runs_on_root_agent_idempotency", unique: true
    t.index ["root_recording_id"], name: "index_rsa_runs_on_root"
    t.index ["status"], name: "index_rsa_runs_on_status"
    t.index ["task_id"], name: "index_rsa_runs_on_task_id"
  end

  create_table "recording_studio_agents_agent_steps", force: :cascade do |t|
    t.bigint "agent_run_id", null: false
    t.integer "sequence", null: false
    t.string "status", null: false
    t.string "action_type", null: false
    t.string "candidate_id"
    t.string "tool_key"
    t.integer "tool_version"
    t.string "argument_digest"
    t.text "observation_summary"
    t.string "observation_digest"
    t.boolean "progress_made"
    t.json "controller_outcome"
    t.bigint "recording_studio_ai_run_id"
    t.boolean "repeatable", default: false, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "record_json", default: {}, null: false
    t.index ["agent_run_id", "sequence"], name: "index_rsa_steps_on_run_and_sequence", unique: true
  end

  create_table "recording_studio_agents_enablements", force: :cascade do |t|
    t.string "agent_key", null: false
    t.integer "agent_version", null: false
    t.boolean "enabled", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_key", "agent_version"], name: "index_rsa_enablements_on_agent", unique: true
  end

  create_table "recording_studio_agents_evaluations", force: :cascade do |t|
    t.bigint "agent_run_id", null: false
    t.string "evaluator_type"
    t.string "evaluator_id"
    t.string "evaluator_key", null: false
    t.integer "evaluator_version", null: false
    t.string "idempotency_key", null: false
    t.string "verdict", null: false
    t.decimal "score", precision: 4, scale: 3
    t.text "notes"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_run_id", "evaluator_key", "evaluator_version", "idempotency_key"], name: "index_rsa_evaluations_on_run_evaluator_idempotency", unique: true
  end

  create_table "recording_studio_agents_run_activities", force: :cascade do |t|
    t.bigint "agent_run_id", null: false
    t.integer "sequence", null: false
    t.string "kind", null: false
    t.json "data", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.index ["agent_run_id", "sequence"], name: "index_rsa_activities_on_run_and_sequence", unique: true
  end

  create_table "recording_studio_agents_tasks", force: :cascade do |t|
    t.uuid "root_recording_id", null: false
    t.uuid "context_recording_id"
    t.string "task_key", null: false
    t.text "goal", null: false
    t.string "input_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["root_recording_id", "task_key"], name: "index_rsa_tasks_on_root_and_key", unique: true
  end

  create_table "recording_studio_ai_attempts", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.integer "sequence", null: false
    t.string "kind", null: false
    t.string "status", default: "pending", null: false
    t.string "profile_key"
    t.string "provider"
    t.string "model"
    t.string "provider_request_id"
    t.boolean "streaming", default: false, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.bigint "latency_ms"
    t.bigint "input_tokens"
    t.bigint "output_tokens"
    t.bigint "total_tokens"
    t.bigint "cached_input_tokens"
    t.bigint "reasoning_tokens"
    t.string "finish_reason"
    t.boolean "retryable"
    t.boolean "web_search_requested", default: false, null: false
    t.boolean "web_search_used", default: false, null: false
    t.integer "citation_count", default: 0, null: false
    t.integer "attachment_count", default: 0, null: false
    t.bigint "attachment_total_bytes", default: 0, null: false
    t.json "attachment_content_types"
    t.integer "provider_file_count"
    t.string "error_category"
    t.string "error_code"
    t.string "error_message"
    t.json "metadata"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "model", "created_at"], name: "idx_rsai_attempts_provider_model_created_at"
    t.index ["provider_request_id"], name: "index_recording_studio_ai_attempts_on_provider_request_id"
    t.index ["run_id", "sequence"], name: "index_recording_studio_ai_attempts_on_run_id_and_sequence", unique: true
    t.index ["run_id"], name: "index_recording_studio_ai_attempts_on_run_id"
    t.index ["status", "created_at"], name: "index_recording_studio_ai_attempts_on_status_and_created_at"
    t.check_constraint "(latency_ms IS NULL OR latency_ms >= 0) AND (input_tokens IS NULL OR input_tokens >= 0) AND (output_tokens IS NULL OR output_tokens >= 0) AND (total_tokens IS NULL OR total_tokens >= 0) AND (cached_input_tokens IS NULL OR cached_input_tokens >= 0) AND (reasoning_tokens IS NULL OR reasoning_tokens >= 0) AND (latency_ms IS NULL OR latency_ms >= 0)", name: "chk_rsai_attempts_nonnegative_metrics"
    t.check_constraint "completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at", name: "chk_rsai_attempts_timeline"
    t.check_constraint "kind::text = ANY (ARRAY['primary'::character varying, 'retry'::character varying, 'fallback'::character varying, 'continuation'::character varying]::text[])", name: "chk_rsai_attempts_kind"
    t.check_constraint "sequence > 0 AND citation_count >= 0 AND attachment_count >= 0 AND attachment_total_bytes >= 0 AND (provider_file_count IS NULL OR provider_file_count >= 0)", name: "chk_rsai_attempts_nonnegative_counts"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying]::text[])", name: "chk_rsai_attempts_status"
  end

  create_table "recording_studio_ai_batch_items", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.bigint "run_id", null: false
    t.integer "position", null: false
    t.string "reference", null: false
    t.string "status", null: false
    t.string "provider_item_id"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.bigint "input_tokens"
    t.bigint "output_tokens"
    t.bigint "total_tokens"
    t.bigint "cached_input_tokens"
    t.bigint "reasoning_tokens"
    t.string "finish_reason"
    t.string "error_category"
    t.string "error_code"
    t.string "error_message"
    t.json "metadata"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id", "position"], name: "index_recording_studio_ai_batch_items_on_batch_id_and_position", unique: true
    t.index ["batch_id", "reference"], name: "idx_on_batch_id_reference_41f755821b", unique: true
    t.index ["provider_item_id"], name: "index_recording_studio_ai_batch_items_on_provider_item_id"
    t.index ["run_id"], name: "index_recording_studio_ai_batch_items_on_run_id", unique: true
    t.index ["status", "created_at"], name: "index_recording_studio_ai_batch_items_on_status_and_created_at"
    t.check_constraint "(input_tokens IS NULL OR input_tokens >= 0) AND (output_tokens IS NULL OR output_tokens >= 0) AND (total_tokens IS NULL OR total_tokens >= 0) AND (cached_input_tokens IS NULL OR cached_input_tokens >= 0) AND (reasoning_tokens IS NULL OR reasoning_tokens >= 0)", name: "chk_rsai_batch_items_nonnegative_metrics"
    t.check_constraint "\"position\" >= 0", name: "chk_rsai_batch_items_position"
    t.check_constraint "completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at", name: "chk_rsai_batch_items_timeline"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'expired'::character varying]::text[])", name: "chk_rsai_batch_items_status"
  end

  create_table "recording_studio_ai_batches", force: :cascade do |t|
    t.string "status", null: false
    t.string "profile_key"
    t.string "provider"
    t.string "model"
    t.string "provider_batch_id"
    t.uuid "root_recording_id", null: false
    t.uuid "context_recording_id"
    t.string "initiator_type", null: false
    t.string "initiator_id", null: false
    t.string "initiator_kind", null: false
    t.string "executor_type"
    t.string "executor_id"
    t.string "executor_kind"
    t.string "execution_source"
    t.string "request_id"
    t.string "job_id"
    t.integer "item_count", default: 0, null: false
    t.integer "completed_item_count", default: 0, null: false
    t.integer "failed_item_count", default: 0, null: false
    t.integer "cancelled_item_count", default: 0, null: false
    t.bigint "input_tokens"
    t.bigint "output_tokens"
    t.bigint "total_tokens"
    t.bigint "cached_input_tokens"
    t.bigint "reasoning_tokens"
    t.datetime "submitted_at"
    t.datetime "completed_at"
    t.datetime "expires_at"
    t.string "error_category"
    t.string "error_code"
    t.string "error_message"
    t.json "metadata"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "impersonator_type"
    t.string "impersonator_id"
    t.index ["context_recording_id"], name: "index_recording_studio_ai_batches_on_context_recording_id"
    t.index ["expires_at"], name: "index_recording_studio_ai_batches_on_expires_at"
    t.index ["impersonator_type", "impersonator_id"], name: "idx_on_impersonator_type_impersonator_id_8de192b4a5"
    t.index ["initiator_type", "initiator_id"], name: "idx_on_initiator_type_initiator_id_b02d5c76ac"
    t.index ["job_id"], name: "index_recording_studio_ai_batches_on_job_id"
    t.index ["provider", "model", "created_at"], name: "idx_rsai_batches_provider_model_created_at"
    t.index ["provider_batch_id"], name: "index_recording_studio_ai_batches_on_provider_batch_id"
    t.index ["request_id"], name: "index_recording_studio_ai_batches_on_request_id"
    t.index ["root_recording_id", "created_at"], name: "idx_on_root_recording_id_created_at_42fdcd79d6"
    t.index ["root_recording_id"], name: "index_recording_studio_ai_batches_on_root_recording_id"
    t.index ["status", "created_at"], name: "index_recording_studio_ai_batches_on_status_and_created_at"
    t.check_constraint "(input_tokens IS NULL OR input_tokens >= 0) AND (output_tokens IS NULL OR output_tokens >= 0) AND (total_tokens IS NULL OR total_tokens >= 0) AND (cached_input_tokens IS NULL OR cached_input_tokens >= 0) AND (reasoning_tokens IS NULL OR reasoning_tokens >= 0)", name: "chk_rsai_batches_nonnegative_metrics"
    t.check_constraint "completed_at IS NULL OR submitted_at IS NULL OR completed_at >= submitted_at", name: "chk_rsai_batches_timeline"
    t.check_constraint "completed_item_count <= item_count AND failed_item_count <= item_count AND cancelled_item_count <= item_count", name: "chk_rsai_batches_item_bounds"
    t.check_constraint "item_count >= 0 AND completed_item_count >= 0 AND failed_item_count >= 0 AND cancelled_item_count >= 0", name: "chk_rsai_batches_nonnegative_counts"
    t.check_constraint "status::text = ANY (ARRAY['preparing'::character varying, 'submitted'::character varying, 'processing'::character varying, 'completed'::character varying, 'partially_completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'expired'::character varying]::text[])", name: "chk_rsai_batches_status"
  end

  create_table "recording_studio_ai_custom_tool_invocations", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.bigint "requested_by_attempt_id"
    t.bigint "continued_by_attempt_id"
    t.string "provider_tool_call_id"
    t.string "tool_key", null: false
    t.integer "tool_version", null: false
    t.string "tool_name_snapshot"
    t.string "status", null: false
    t.boolean "read_only", null: false
    t.boolean "destructive", null: false
    t.boolean "requires_confirmation", null: false
    t.boolean "idempotent", null: false
    t.string "latency_category"
    t.string "confirmation_status"
    t.string "confirmed_by_type"
    t.string "confirmed_by_id"
    t.datetime "confirmed_at"
    t.text "result_summary"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.bigint "latency_ms"
    t.string "error_category"
    t.string "error_code"
    t.string "error_message"
    t.json "metadata"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "arguments"
    t.json "result"
    t.index ["confirmation_status", "created_at"], name: "idx_rsai_tool_invocations_confirmation"
    t.index ["continued_by_attempt_id"], name: "idx_rsai_tool_invocations_continued_attempt"
    t.index ["provider_tool_call_id"], name: "idx_on_provider_tool_call_id_c470d20051"
    t.index ["requested_by_attempt_id"], name: "idx_rsai_tool_invocations_requested_attempt"
    t.index ["run_id", "created_at"], name: "idx_rsai_tool_invocations_run_created_at"
    t.index ["run_id"], name: "index_recording_studio_ai_custom_tool_invocations_on_run_id"
    t.index ["status", "created_at"], name: "idx_on_status_created_at_3871597917"
    t.index ["tool_key", "created_at"], name: "idx_on_tool_key_created_at_f4175f8648"
    t.check_constraint "completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at", name: "chk_rsai_tool_invocations_timeline"
    t.check_constraint "confirmation_status IS NULL OR (confirmation_status::text = ANY (ARRAY['not_required'::character varying, 'pending'::character varying, 'confirmed'::character varying, 'rejected'::character varying, 'expired'::character varying]::text[]))", name: "chk_rsai_tool_invocations_confirmation_status"
    t.check_constraint "confirmation_status::text = 'confirmed'::text AND confirmed_by_type IS NOT NULL AND confirmed_by_id IS NOT NULL AND confirmed_at IS NOT NULL OR confirmation_status::text <> 'confirmed'::text AND confirmed_by_type IS NULL AND confirmed_by_id IS NULL AND confirmed_at IS NULL OR confirmation_status IS NULL", name: "chk_rsai_tool_invocations_confirmer"
    t.check_constraint "latency_category IS NULL OR (latency_category::text = ANY (ARRAY['instant'::character varying, 'fast'::character varying, 'slow'::character varying]::text[]))", name: "chk_rsai_tool_invocations_latency_category"
    t.check_constraint "latency_ms IS NULL OR latency_ms >= 0", name: "chk_rsai_tool_invocations_latency"
    t.check_constraint "status::text = ANY (ARRAY['requested'::character varying, 'awaiting_confirmation'::character varying, 'authorized'::character varying, 'running'::character varying, 'completed'::character varying, 'denied'::character varying, 'rejected'::character varying, 'failed'::character varying, 'cancelled'::character varying]::text[])", name: "chk_rsai_tool_invocations_status"
  end

  create_table "recording_studio_ai_responses", force: :cascade do |t|
    t.bigint "attempt_id"
    t.bigint "batch_item_id"
    t.string "provider"
    t.string "model"
    t.string "provider_response_id"
    t.string "response_type", null: false
    t.text "raw_response"
    t.text "normalized_response"
    t.text "content_text"
    t.string "content_type"
    t.string "finish_reason"
    t.boolean "complete"
    t.boolean "truncated"
    t.bigint "byte_size"
    t.datetime "expires_at", null: false
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attempt_id"], name: "index_recording_studio_ai_responses_on_attempt_id", unique: true
    t.index ["batch_item_id"], name: "index_recording_studio_ai_responses_on_batch_item_id", unique: true
    t.index ["expires_at"], name: "index_recording_studio_ai_responses_on_expires_at"
    t.index ["provider", "model", "created_at"], name: "idx_rsai_responses_provider_model_created_at"
    t.index ["provider_response_id"], name: "index_recording_studio_ai_responses_on_provider_response_id"
    t.check_constraint "attempt_id IS NOT NULL AND batch_item_id IS NULL OR attempt_id IS NULL AND batch_item_id IS NOT NULL", name: "chk_rsai_responses_attempt_xor_batch_item"
    t.check_constraint "byte_size IS NULL OR byte_size >= 0", name: "chk_rsai_responses_nonnegative_byte_size"
    t.check_constraint "response_type::text = ANY (ARRAY['generation'::character varying, 'stream'::character varying, 'batch_item'::character varying, 'error'::character varying, 'decision'::character varying]::text[])", name: "chk_rsai_responses_type"
  end

  create_table "recording_studio_ai_runs", force: :cascade do |t|
    t.string "operation", null: false
    t.string "purpose"
    t.string "status", default: "pending", null: false
    t.string "profile_key"
    t.string "requested_provider"
    t.string "resolved_provider"
    t.string "resolved_model"
    t.uuid "root_recording_id", null: false
    t.uuid "context_recording_id"
    t.string "initiator_type", null: false
    t.string "initiator_id", null: false
    t.string "initiator_kind", null: false
    t.string "executor_type"
    t.string "executor_id"
    t.string "executor_kind"
    t.string "impersonator_type"
    t.string "impersonator_id"
    t.string "execution_source"
    t.string "request_id"
    t.string "job_id"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.bigint "latency_ms"
    t.bigint "input_tokens"
    t.bigint "output_tokens"
    t.bigint "total_tokens"
    t.bigint "cached_input_tokens"
    t.bigint "reasoning_tokens"
    t.integer "attempt_count", default: 0, null: false
    t.integer "retry_count", default: 0, null: false
    t.integer "fallback_count", default: 0, null: false
    t.integer "custom_tool_invocation_count", default: 0, null: false
    t.integer "input_character_count"
    t.integer "output_character_count"
    t.integer "attachment_count", default: 0, null: false
    t.bigint "attachment_total_bytes", default: 0, null: false
    t.json "attachment_content_types"
    t.integer "citation_count", default: 0, null: false
    t.boolean "web_search_requested", default: false, null: false
    t.boolean "web_search_used", default: false, null: false
    t.string "error_category"
    t.string "error_code"
    t.string "error_message"
    t.json "metadata"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "prompt_key"
    t.integer "prompt_version"
    t.string "prompt_name_snapshot"
    t.index ["context_recording_id"], name: "index_recording_studio_ai_runs_on_context_recording_id"
    t.index ["executor_type", "executor_id"], name: "idx_on_executor_type_executor_id_ff99c66eda"
    t.index ["initiator_type", "initiator_id"], name: "idx_on_initiator_type_initiator_id_c688e18770"
    t.index ["job_id"], name: "index_recording_studio_ai_runs_on_job_id"
    t.index ["profile_key", "created_at"], name: "index_recording_studio_ai_runs_on_profile_key_and_created_at"
    t.index ["prompt_key", "prompt_version", "created_at"], name: "idx_rsai_runs_prompt_created_at"
    t.index ["purpose", "created_at"], name: "index_recording_studio_ai_runs_on_purpose_and_created_at"
    t.index ["request_id"], name: "index_recording_studio_ai_runs_on_request_id"
    t.index ["resolved_provider", "resolved_model", "created_at"], name: "idx_rsai_runs_provider_model_created_at"
    t.index ["root_recording_id", "created_at"], name: "idx_on_root_recording_id_created_at_22709d290f"
    t.index ["root_recording_id"], name: "index_recording_studio_ai_runs_on_root_recording_id"
    t.index ["status", "created_at"], name: "index_recording_studio_ai_runs_on_status_and_created_at"
    t.check_constraint "(latency_ms IS NULL OR latency_ms >= 0) AND (input_tokens IS NULL OR input_tokens >= 0) AND (output_tokens IS NULL OR output_tokens >= 0) AND (total_tokens IS NULL OR total_tokens >= 0) AND (cached_input_tokens IS NULL OR cached_input_tokens >= 0) AND (reasoning_tokens IS NULL OR reasoning_tokens >= 0) AND (input_character_count IS NULL OR input_character_count >= 0) AND (output_character_count IS NULL OR output_character_count >= 0)", name: "chk_rsai_runs_nonnegative_metrics"
    t.check_constraint "attachment_count >= 0 AND attachment_total_bytes >= 0 AND citation_count >= 0", name: "chk_rsai_runs_nonnegative_attachment_counts"
    t.check_constraint "attempt_count >= 0 AND retry_count >= 0 AND fallback_count >= 0 AND custom_tool_invocation_count >= 0", name: "chk_rsai_runs_nonnegative_counts"
    t.check_constraint "completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at", name: "chk_rsai_runs_timeline"
    t.check_constraint "operation::text = ANY (ARRAY['generation'::character varying, 'stream'::character varying, 'batch'::character varying, 'decision'::character varying, 'tool'::character varying]::text[])", name: "chk_rsai_runs_operation"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying]::text[])", name: "chk_rsai_runs_status"
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

  create_table "recording_studio_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "recording_id", null: false
    t.string "action", null: false
    t.string "recordable_type", null: false
    t.uuid "recordable_id", null: false
    t.string "previous_recordable_type"
    t.uuid "previous_recordable_id"
    t.string "actor_type"
    t.uuid "actor_id"
    t.string "impersonator_type"
    t.uuid "impersonator_id"
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "idempotency_key"
    t.datetime "created_at", null: false
    t.index ["action", "occurred_at"], name: "index_rs_events_on_action_and_occurred_at"
    t.index ["actor_type", "actor_id", "occurred_at"], name: "index_rs_events_on_actor_and_occurred_at"
    t.index ["recording_id", "idempotency_key"], name: "index_recording_studio_events_on_recording_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recording_id", "occurred_at", "created_at"], name: "index_rs_events_on_recording_and_timeline", order: { occurred_at: :desc, created_at: :desc }
    t.index ["recording_id"], name: "index_recording_studio_events_on_recording_id"
  end

  create_table "recording_studio_recordings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "recordable_type", null: false
    t.uuid "recordable_id", null: false
    t.datetime "trashed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "parent_recording_id"
    t.uuid "root_recording_id"
    t.index ["parent_recording_id"], name: "index_recording_studio_recordings_on_parent_recording_id"
    t.index ["recordable_type", "recordable_id", "parent_recording_id", "trashed_at"], name: "index_recording_studio_recordings_on_recordable_parent_trashed"
    t.index ["recordable_type", "recordable_id"], name: "index_recording_studio_recordings_on_recordable"
    t.index ["recordable_type", "recordable_id"], name: "index_rs_unique_root_recording_per_recordable", unique: true, where: "(parent_recording_id IS NULL)"
    t.index ["root_recording_id", "parent_recording_id"], name: "index_rs_recordings_on_root_and_parent"
    t.index ["root_recording_id", "recordable_type", "recordable_id"], name: "index_rs_recordings_on_root_and_recordable"
    t.index ["root_recording_id"], name: "index_rs_recordings_on_root_recording"
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

  create_table "recording_studio_web_search_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "provider", null: false
    t.string "query", null: false
    t.string "status", null: false
    t.string "outcome", null: false
    t.integer "result_count"
    t.integer "duration_ms"
    t.decimal "estimated_cost_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.jsonb "parameters", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "results", default: [], null: false
    t.index ["created_at"], name: "index_recording_studio_web_search_runs_on_created_at"
    t.index ["provider"], name: "index_recording_studio_web_search_runs_on_provider"
    t.index ["status"], name: "index_recording_studio_web_search_runs_on_status"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "recording_studio_access_invitations", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_agents_agent_runs", "recording_studio_agents_tasks", column: "task_id"
  add_foreign_key "recording_studio_agents_agent_steps", "recording_studio_agents_agent_runs", column: "agent_run_id"
  add_foreign_key "recording_studio_agents_evaluations", "recording_studio_agents_agent_runs", column: "agent_run_id"
  add_foreign_key "recording_studio_agents_run_activities", "recording_studio_agents_agent_runs", column: "agent_run_id"
  add_foreign_key "recording_studio_ai_attempts", "recording_studio_ai_runs", column: "run_id"
  add_foreign_key "recording_studio_ai_batch_items", "recording_studio_ai_batches", column: "batch_id"
  add_foreign_key "recording_studio_ai_batch_items", "recording_studio_ai_runs", column: "run_id"
  add_foreign_key "recording_studio_ai_batches", "recording_studio_recordings", column: "context_recording_id"
  add_foreign_key "recording_studio_ai_batches", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_ai_custom_tool_invocations", "recording_studio_ai_attempts", column: "continued_by_attempt_id"
  add_foreign_key "recording_studio_ai_custom_tool_invocations", "recording_studio_ai_attempts", column: "requested_by_attempt_id"
  add_foreign_key "recording_studio_ai_custom_tool_invocations", "recording_studio_ai_runs", column: "run_id"
  add_foreign_key "recording_studio_ai_responses", "recording_studio_ai_attempts", column: "attempt_id"
  add_foreign_key "recording_studio_ai_responses", "recording_studio_ai_batch_items", column: "batch_item_id"
  add_foreign_key "recording_studio_ai_runs", "recording_studio_recordings", column: "context_recording_id"
  add_foreign_key "recording_studio_ai_runs", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_api_api_access_tokens", "recording_studio_api_api_credentials", column: "api_credential_id"
  add_foreign_key "recording_studio_api_api_credentials", "recording_studio_api_api_clients", column: "api_client_id"
  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "parent_recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "root_recording_id"
end
