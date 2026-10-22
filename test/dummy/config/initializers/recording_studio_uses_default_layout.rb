# frozen_string_literal: true

# Recording Studio 5.0.0 removed RecordingStudio::UsesDefaultLayout.
# Oauth v0.12.5 and Site Settings v0.5.1 still include it, and no published
# tag of either gem has switched to recording_studio_layout. Define the old
# name so those controllers boot, and resolve the layout the 5.0 way.
unless defined?(RecordingStudio::UsesDefaultLayout)
  module RecordingStudio
    module UsesDefaultLayout
      extend ActiveSupport::Concern

      included do
        recording_studio_layout
      end
    end
  end
end
