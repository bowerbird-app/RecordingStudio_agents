# frozen_string_literal: true

module RecordingStudioAgents
  module Mcp
    # Shares the Recording Studio API read and write windows. A signed-in person
    # with no API credential is counted as that actor.
    module ChatToolLimit
      module_function

      def limited?(grant, name, actor)
        return false unless defined?(RecordingStudioApi::Concerns::RateLimiting)

        policy = RecordingStudioApi::ApiRuntimePolicy.for(ChatToolCall.api_key(grant))
        return false unless policy.rate_limit_api_enabled

        over_limit?(policy, rate_bucket(grant, name), grant, actor)
      end

      def over_limit?(policy, bucket, grant, actor)
        limit, period = rate_window(policy, bucket)
        return false if limit <= 0 || period <= 0

        redis = RecordingStudioApi::Concerns::RateLimiting.redis_client
        return fail_closed?(bucket) if redis.nil?

        increment(redis, counter_key(grant, bucket, actor, period), period) > limit
      rescue *ChatToolCall.store_errors => e
        ChatToolCall.log_call_error(e)
        fail_closed?(bucket)
      end

      def rate_bucket(grant, name)
        read = RecordingStudioMcp::ToolSurface.for(access_grant: grant).read_only_tool?(name)
        read ? "api_read" : "api_write"
      end

      def rate_window(policy, bucket)
        limit, period = bucket == "api_read" ? read_window(policy) : write_window(policy)
        limit = policy.rate_limit_api_requests.to_i if limit <= 0
        period = policy.rate_limit_api_period_seconds.to_i if period <= 0
        [limit, period]
      end

      def read_window(policy)
        [policy.rate_limit_api_read_requests.to_i, policy.rate_limit_api_read_period_seconds.to_i]
      end

      def write_window(policy)
        [policy.rate_limit_api_write_requests.to_i, policy.rate_limit_api_write_period_seconds.to_i]
      end

      def increment(redis, key, period)
        script = RecordingStudioApi::Concerns::RateLimiting::RATE_LIMIT_INCR_EXPIRE_SCRIPT
        return redis.eval(script, keys: [key], argv: [period.to_i])[0].to_i if redis.respond_to?(:eval)

        count = redis.incr(key).to_i
        redis.expire(key, period) if count == 1
        count
      end

      def counter_key(grant, bucket, actor, period)
        window = Time.current.to_i / period
        "#{namespace_for(grant)}:#{bucket}:#{identifier_for(grant, actor)}:#{window}"
      end

      def namespace_for(grant)
        configured = RecordingStudioApi.configuration.rate_limit_redis_namespace.to_s.strip
        base = configured.present? ? configured : "recording_studio_api"
        key = ChatToolCall.api_key(grant)
        return base if key.blank? || key == "public"

        "#{base}:#{key}"
      end

      def identifier_for(grant, actor)
        return "credential:#{grant.credential.id}" if grant.credential&.id
        return "client:#{grant.api_client.id}" if grant.api_client&.id

        "actor:#{actor.class.name}:#{actor.id}"
      end

      def fail_closed?(bucket)
        return false unless RecordingStudioApi.configuration.rate_limit_fail_closed

        buckets = Array(RecordingStudioApi.configuration.rate_limit_fail_closed_buckets).map(&:to_s)
        buckets.include?(bucket.to_s)
      end
    end
  end
end
