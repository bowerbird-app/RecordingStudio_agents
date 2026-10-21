# Start screens for the workspace press-kit list and for one kit.
class PressKitChat
  def self.workspace
    screen(
      greeting: "Which press kit should we open?",
      placeholder: "Ask about these press kits",
      prompts: [
        [ "Summarize the kits", "Summarize the press kits in this workspace.", "search" ],
        [ "Compare the street stories", "Which press kit has the stronger street story?", "write" ]
      ]
    )
  end

  def self.for_kit(recording)
    name = recording.recordable.name
    screen(
      greeting: "What should we pull from this kit?",
      placeholder: "Ask about #{name}",
      prompts: [
        [ "Intro for this kit", "Write a short intro for #{name}.", "write" ],
        [ "Awards on this kit", "List the awards on #{name}.", "search" ]
      ]
    )
  end

  def self.screen(greeting:, placeholder:, prompts:)
    {
      startScreen: {
        greeting: greeting,
        prompts: prompts.map { |label, prompt, icon| { label: label, prompt: prompt, icon: icon } }
      },
      composer: { placeholder: placeholder },
      header: { enabled: true },
      history: { enabled: true, showDelete: true, showRename: true },
      initialThread: nil,
      theme: { colorScheme: "light", radius: "round" }
    }
  end
  private_class_method :screen
end
