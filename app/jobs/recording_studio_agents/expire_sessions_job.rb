# frozen_string_literal: true

module RecordingStudioAgents
  class ExpireSessionsJob < ActiveJob::Base
    def perform
      Sessions::Expire.call.value!
    end
  end
end
