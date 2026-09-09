# frozen_string_literal: true

module RecordingStudioAgents
  module Admin
    # Admin section hubs pass `url:` into Flatpack Button. Flatpack only reads
    # `href:`, so those title buttons render as inert `<button>` tags.
    # This prepend maps `url` to `href` until Admin ships `href:` on that
    # template. Do not copy this prepend in a host.
    module FlatpackButtonUrl
      def initialize(url: nil, href: nil, **system_arguments)
        super(href: href || url, **system_arguments)
      end
    end
  end
end
