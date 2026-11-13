# frozen_string_literal: true

# recording_studio_ai.execute maps to :edit on the workspace through Accessible.
# Do not allow every signed-in person.
RecordingStudioAI.configure do |config|
  config.authorization_handler = RecordingStudioAI::AccessibleAuthorization.method(:call)
end
