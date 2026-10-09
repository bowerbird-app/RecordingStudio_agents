# frozen_string_literal: true

require "test_helper"

class ApiAccessTest < Minitest::Test
  def test_site_resolver_is_preferred_when_set
    actor = Object.new
    site_recording = Object.new
    access_called = false
    decision = nil

    with_resolvers(
      site: lambda { |context|
        assert_nil context.controller
        site_recording
      },
      access: lambda { |*|
        access_called = true
        flunk "site resolver should be used"
      }
    ) do
      RecordingStudioAccessible.stub(:authorized?, lambda { |actor:, recording:, role:|
        decision = { actor: actor, recording: recording, role: role }
        true
      }) do
        assert_equal true, RecordingStudioAgents::Api::Access.can_view?(view_context(actor))
      end
    end

    refute access_called
    assert_equal actor, decision[:actor]
    assert_equal site_recording, decision[:recording]
    assert_equal :view, decision[:role]
  end

  def test_access_resolver_is_used_when_site_resolver_is_unset
    actor = Object.new
    access_recording = Object.new
    decision = nil

    with_resolvers(
      site: nil,
      access: lambda { |context|
        assert_nil context.controller
        access_recording
      }
    ) do
      RecordingStudioAccessible.stub(:authorized?, lambda { |actor:, recording:, role:|
        decision = { actor: actor, recording: recording, role: role }
        false
      }) do
        assert_equal false, RecordingStudioAgents::Api::Access.can_view?(view_context(actor))
      end
    end

    assert_equal actor, decision[:actor]
    assert_equal access_recording, decision[:recording]
    assert_equal :view, decision[:role]
  end

  def test_resolver_error_denies_without_raising
    with_resolvers(
      site: ->(*) { raise NoMethodError, "undefined method for nil" },
      access: ->(*) { flunk "site resolver should be used" }
    ) do
      RecordingStudioAccessible.stub(:authorized?, ->(**) { flunk "should not decide" }) do
        assert_equal false, RecordingStudioAgents::Api::Access.can_view?(view_context(Object.new))
      end
    end
  end

  def test_nil_resolver_result_denies
    access_called = false

    with_resolvers(
      site: ->(*) {},
      access: lambda { |*|
        access_called = true
        Object.new
      }
    ) do
      RecordingStudioAccessible.stub(:authorized?, ->(**) { flunk "should not decide" }) do
        assert_equal false, RecordingStudioAgents::Api::Access.can_view?(view_context(Object.new))
      end
    end

    refute access_called
  end

  private

  def view_context(actor)
    grant = Struct.new(:actor).new(actor)
    Struct.new(:access_grant).new(grant)
  end

  def with_resolvers(site:, access:)
    config = RecordingStudioAdmin.configuration
    original_site = config.site_admin_recording_resolver
    original_access = config.access_recording_resolver
    config.site_admin_recording_resolver = site
    config.access_recording_resolver = access
    yield
  ensure
    config.site_admin_recording_resolver = original_site
    config.access_recording_resolver = original_access
  end
end
