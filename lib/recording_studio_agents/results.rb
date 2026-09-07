# frozen_string_literal: true

module RecordingStudioAgents
  class Citation
    attr_reader :title, :url

    def initialize(title:, url:)
      @title = title.to_s
      @url = url.to_s
      freeze
    end
  end

  class Output
    attr_reader :text, :data, :citations

    def initialize(text:, data:, citations:)
      @text = text
      @data = data
      @citations = Array(citations)
      freeze
    end
  end

  class Failure
    attr_reader :category, :code, :message, :retryable

    def initialize(category:, code:, message:, retryable:)
      @category = category.to_s
      @code = code.to_s
      @message = message.to_s
      @retryable = retryable == true
      freeze
    end

    def retryable?
      retryable
    end
  end

  class HandoffRequest
    attr_reader :target

    def initialize(target:)
      @target = target
      freeze
    end
  end

  module Results
    class Completed
      attr_reader :run, :output

      def initialize(run:, output:)
        @run = run
        @output = output
      end
    end

    class HandoffRequested
      attr_reader :run, :request

      def initialize(run:, request:)
        @run = run
        @request = request
      end
    end

    class Failed
      attr_reader :run, :failure

      def initialize(run:, failure:)
        @run = run
        @failure = failure
      end
    end

    class Existing
      attr_reader :run

      def initialize(run:)
        @run = run
      end
    end

    class InProgress
      attr_reader :run

      def initialize(run:)
        @run = run
      end
    end

    class Blocked
      attr_reader :run

      def initialize(run:)
        @run = run
      end
    end
  end
end
