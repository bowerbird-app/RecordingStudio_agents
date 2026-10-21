# One page declaration: the recording scopes the chat, and these options are the start screen.
class PressKitPageChat
  def self.for(recording)
    new(recording)
  end

  def initialize(recording)
    @recording = recording
  end

  def page_recording
    @recording
  end

  def chatkit_options
    self.class.options
  end

  def self.options
    {
      startScreen: {
        greeting: "What should we make for this page?",
        prompts: [
          { label: "Create a PressKit.", prompt: "Create a PressKit.", icon: "write" },
          {
            label: "Show me an example of a PressKit",
            prompt: "Show me an example of a PressKit",
            icon: "search"
          }
        ]
      },
      composer: { placeholder: "Ask about this page" },
      header: { enabled: true, title: { enabled: true, text: "Press kit" } },
      history: { enabled: true, showDelete: true, showRename: true },
      initialThread: nil,
      theme: { colorScheme: "light", radius: "round" }
    }
  end
end
